// POST /functions/v1/address-suggest
//
// Australian address suggestions for the client form. The browser sends the
// text the user has typed; this function calls Places API (New) with a key
// that never leaves the server.
//
//   { "action": "autocomplete", "input": "12 watt clyde", "sessionToken": "<uuid v4>" }
//   { "action": "details", "placeId": "ChIJ...", "sessionToken": "<uuid v4>" }
//
// The same sessionToken must be sent on the autocomplete calls and the one
// Place Details call that follows a choice, so Google bills that round-trip
// as a single session. The browser rotates the token after a choice or when
// the user leaves the address.
//
// Env (Supabase function secret, never in the repo, never in index.html):
//   GOOGLE_PLACES_API_KEY   Google Cloud API key restricted to Places API (New).
//                           If it is unset, the response is { configured: false }
//                           and the form keeps working as plain text fields.
//
// Auth: verify_jwt = true in config.toml. The gateway rejects anonymous
// callers before this code runs. A bearer token is still required here so a
// mistaken verify_jwt = false cannot turn the function into an open proxy
// for the Google key. The signature itself is checked by the gateway.
//
// No database access, no service-role key, no device location. Results are
// restricted to Australia and biased to the Australian continent (a fixed
// box, not the caller's GPS or IP).

import { reportError } from "../_shared/sentry.ts";
import { parseAddressComponents, type ParsedAddress } from "./parse.ts";

const PLACES = "https://places.googleapis.com/v1";
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PLACE_ID = /^[A-Za-z0-9_-]{8,250}$/;
const AUTOCOMPLETE_TYPES = ["street_address", "route", "premise", "subpremise"];

// Fixed box around Australia. Bias only — includedRegionCodes is what
// actually drops non-Australian results. Not derived from the user.
const AUSTRALIA_BIAS = {
  rectangle: {
    low: { latitude: -44.0, longitude: 112.0 },
    high: { latitude: -10.0, longitude: 154.0 },
  },
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

// Sliding window per signed-in user. The client's debounce stays under this;
// a tight loop cannot drain the Google key. A fixed window (not a refill
// rate) keeps the limit stable when several calls land in the same instant.
const WINDOW_MS = 10_000;
const MAX_IN_WINDOW = 12;
const hits = new Map<string, number[]>();

export function resetRateLimits(): void {
  hits.clear();
}

function limited(id: string): boolean {
  const now = Date.now();
  const recent = (hits.get(id) ?? []).filter((t) => now - t < WINDOW_MS);
  if (recent.length >= MAX_IN_WINDOW) {
    hits.set(id, recent);
    return true;
  }
  recent.push(now);
  hits.set(id, recent);
  if (hits.size > 500) {
    const oldest = hits.keys().next().value;
    if (oldest) hits.delete(oldest);
  }
  return false;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function placesKey(): string {
  return (Deno.env.get("GOOGLE_PLACES_API_KEY") ?? "").trim();
}

/** sub claim of the bearer token. The gateway has already verified the signature. */
export function callerSub(req: Request): string {
  const h = req.headers.get("Authorization") ?? "";
  if (!h.startsWith("Bearer ")) return "";
  const part = h.slice("Bearer ".length).trim().split(".");
  if (part.length !== 3 || !part[1]) return "";
  try {
    const pad = part[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(pad + "===".slice((pad.length + 3) % 4))) as { sub?: unknown; exp?: unknown };
    const sub = typeof payload.sub === "string" ? payload.sub : "";
    if (!/^[0-9a-f-]{8,80}$/i.test(sub)) return "";
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now() - 120_000) return "";
    return sub;
  } catch {
    return "";
  }
}

interface Suggestion {
  placeId: string;
  mainText: string;
  secondaryText: string;
}

function suggestionFrom(raw: unknown): Suggestion | null {
  if (!raw || typeof raw !== "object") return null;
  const place = (raw as { placePrediction?: unknown }).placePrediction;
  if (!place || typeof place !== "object") return null;
  const p = place as {
    placeId?: unknown;
    text?: { text?: unknown };
    structuredFormat?: { mainText?: { text?: unknown }; secondaryText?: { text?: unknown } };
    types?: unknown;
  };
  const placeId = typeof p.placeId === "string" ? p.placeId : "";
  if (!PLACE_ID.test(placeId)) return null;
  const types = Array.isArray(p.types) ? p.types.filter((t): t is string => typeof t === "string") : [];
  // includedPrimaryTypes should already have done this. Drop a business that
  // slipped through without an address type.
  const addressy = types.some((t) =>
    t === "street_address" || t === "route" || t === "premise" || t === "subpremise" || t === "geocode"
  );
  if (types.length && !addressy) return null;
  const main = typeof p.structuredFormat?.mainText?.text === "string"
    ? p.structuredFormat.mainText.text
    : (typeof p.text?.text === "string" ? p.text.text : "");
  const secondary = typeof p.structuredFormat?.secondaryText?.text === "string"
    ? p.structuredFormat.secondaryText.text
    : "";
  const mainText = main.replace(/\s+/g, " ").trim().slice(0, 180);
  if (!mainText) return null;
  return { placeId, mainText, secondaryText: secondary.replace(/\s+/g, " ").trim().slice(0, 180) };
}

function headerRecord(h: HeadersInit | undefined): Record<string, string> {
  if (!h) return {};
  if (h instanceof Headers) {
    const o: Record<string, string> = {};
    h.forEach((v, k) => {
      o[k] = v;
    });
    return o;
  }
  if (Array.isArray(h)) return Object.fromEntries(h);
  return { ...h };
}

async function google(url: string, init: RequestInit): Promise<Response | "unconfigured" | "down"> {
  const key = placesKey();
  if (!key) return "unconfigured";
  try {
    return await fetch(url, {
      ...init,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": key,
        ...headerRecord(init.headers),
      },
      signal: AbortSignal.timeout(5000),
    });
  } catch (e) {
    // Do not include the request: the body is the address the user typed.
    console.error("address-suggest google unreachable");
    await reportError("address-suggest", e);
    return "down";
  }
}

function empty(configured: boolean, extra: Record<string, unknown> = {}): Response {
  return json(200, { configured, suggestions: [], ...extra });
}

export async function handleAddressSuggest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { configured: false, error: "POST only" });

  const len = Number(req.headers.get("content-length") || "0");
  if (len > 4000) return json(400, { configured: true, error: "Request too large" });

  if (!placesKey()) return empty(false);

  const sub = callerSub(req);
  if (!sub) return json(401, { configured: true, error: "Sign in first." });
  if (limited(sub)) return empty(true, { limited: true });

  let body: Record<string, unknown>;
  try {
    const parsed = await req.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return json(400, { configured: true, error: "Expected an object" });
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return json(400, { configured: true, error: "Unreadable body" });
  }

  const action = body.action;
  const sessionToken = typeof body.sessionToken === "string" ? body.sessionToken : "";
  if (!UUID_V4.test(sessionToken)) return json(400, { configured: true, error: "sessionToken must be a UUID v4" });

  if (action === "autocomplete") {
    const input = typeof body.input === "string" ? body.input.replace(/\s+/g, " ").trim() : "";
    if (input.length < 3 || input.length > 200) return empty(true);
    const mask = {
      "X-Goog-FieldMask":
        "suggestions.placePrediction.placeId,suggestions.placePrediction.text,suggestions.placePrediction.structuredFormat,suggestions.placePrediction.types",
    };
    const payloadFor = (types: boolean) => JSON.stringify({
      input,
      sessionToken,
      includedRegionCodes: ["au"],
      ...(types ? { includedPrimaryTypes: AUTOCOMPLETE_TYPES } : {}),
      languageCode: "en-AU",
      regionCode: "au",
      locationBias: AUSTRALIA_BIAS,
    });
    let res = await google(`${PLACES}/places:autocomplete`, {
      method: "POST",
      headers: mask,
      body: payloadFor(true),
    });
    // A 400 here is usually "that primary type is not accepted". Retry once
    // without the type filter; businesses are still dropped in suggestionFrom.
    if (res instanceof Response && res.status === 400) {
      res = await google(`${PLACES}/places:autocomplete`, {
        method: "POST",
        headers: mask,
        body: payloadFor(false),
      });
    }
    if (res === "unconfigured") return empty(false);
    if (res === "down" || (res instanceof Response && (res.status === 401 || res.status === 403))) {
      return empty(true, { unavailable: true });
    }
    if (!(res instanceof Response) || !res.ok) {
      if (res instanceof Response) console.error("address-suggest google status", res.status);
      return empty(true);
    }
    let payload: { suggestions?: unknown[] } = {};
    try {
      payload = await res.json();
    } catch {
      return empty(true, { unavailable: true });
    }
    const suggestions = (Array.isArray(payload.suggestions) ? payload.suggestions : [])
      .map(suggestionFrom)
      .filter((s): s is Suggestion => !!s)
      .slice(0, 5);
    return json(200, { configured: true, suggestions });
  }

  if (action === "details") {
    const placeId = typeof body.placeId === "string" ? body.placeId : "";
    if (!PLACE_ID.test(placeId)) return json(400, { configured: true, error: "Invalid place" });
    const url = `${PLACES}/places/${placeId}?sessionToken=${encodeURIComponent(sessionToken)}&languageCode=en-AU&regionCode=au`;
    const res = await google(url, {
      method: "GET",
      headers: { "X-Goog-FieldMask": "addressComponents" },
    });
    if (res === "unconfigured") return empty(false);
    if (res === "down" || (res instanceof Response && (res.status === 401 || res.status === 403))) {
      return json(200, { configured: true, address: null, unavailable: true });
    }
    if (!(res instanceof Response) || !res.ok) {
      if (res instanceof Response) console.error("address-suggest google status", res.status);
      return json(200, { configured: true, address: null });
    }
    let payload: { addressComponents?: unknown } = {};
    try {
      payload = await res.json();
    } catch {
      return json(200, { configured: true, address: null, unavailable: true });
    }
    const parsed: ParsedAddress | null = parseAddressComponents(
      payload.addressComponents as Parameters<typeof parseAddressComponents>[0],
    );
    if (!parsed || !parsed.inAustralia) return json(200, { configured: true, address: null });
    return json(200, {
      configured: true,
      address: {
        streetNumber: parsed.streetNumber,
        streetName: parsed.streetName,
        suburb: parsed.suburb,
        estate: parsed.estate,
      },
    });
  }

  return json(400, { configured: true, error: "Unknown action" });
}
