// deno test -A supabase/functions/address-suggest/address_suggest_test.ts
// No network. No Google key. Confirms the form-facing fallback and that the
// outgoing Places request is Australia-only and carries the session token.
import { parseAddressComponents } from "./parse.ts";
import { callerSub, handleAddressSuggest, resetRateLimits } from "./handler.ts";

function assert(cond: unknown, msg: string): asserts cond {
  if (!cond) throw new Error(msg);
}

const eq = (a: unknown, b: unknown, msg: string) => {
  const ja = JSON.stringify(a);
  const jb = JSON.stringify(b);
  if (ja !== jb) throw new Error(`${msg}\n  ${ja}\n  ${jb}`);
};

function component(longText: string, types: string[], shortText?: string) {
  return { longText, shortText: shortText ?? longText, types };
}

Deno.test("parse: street, suburb, and no estate when Google has no neighbourhood", () => {
  const parsed = parseAddressComponents([
    component("12", ["street_number"]),
    component("Wattle Grove", ["route"]),
    component("Clyde North", ["locality", "political"]),
    component("Casey", ["administrative_area_level_2", "political"]),
    component("Victoria", ["administrative_area_level_1", "political"], "VIC"),
    component("3978", ["postal_code"]),
    component("Australia", ["country", "political"], "AU"),
  ]);
  eq(parsed && {
    streetNumber: parsed.streetNumber,
    streetName: parsed.streetName,
    suburb: parsed.suburb,
    estate: parsed.estate,
    inAustralia: parsed.inAustralia,
  }, {
    streetNumber: "12",
    streetName: "Wattle Grove",
    suburb: "Clyde North",
    estate: null,
    inAustralia: true,
  }, "standard address");
});

Deno.test("parse: neighborhood becomes estate, but not when it repeats the suburb", () => {
  const withEstate = parseAddressComponents([
    component("8", ["street_number"]),
    component("Meridian Drive", ["route"]),
    component("Clyde North", ["locality"]),
    component("Meridian Estate", ["neighborhood", "political"]),
    component("Australia", ["country"], "AU"),
  ]);
  assert(withEstate?.estate === "Meridian Estate", "estate from neighborhood");

  const same = parseAddressComponents([
    component("8", ["street_number"]),
    component("High Street", ["route"]),
    component("Richmond", ["locality"]),
    component("Richmond", ["neighborhood"]),
    component("Australia", ["country"], "AU"),
  ]);
  assert(same?.estate === null, "suburb-shaped neighborhood is not an estate");
});

Deno.test("parse: sublocality is a suburb fallback, never an estate; unit numbers use a slash", () => {
  const parsed = parseAddressComponents([
    component("Unit 2", ["subpremise"]),
    component("14", ["street_number"]),
    component("Example Street", ["route"]),
    component("Southbank", ["sublocality_level_1", "political"]),
    component("Display Village", ["premise"]),
    component("Australia", ["country"], "AU"),
  ]);
  assert(parsed?.streetNumber === "2/14", "unit slash form");
  assert(parsed?.suburb === "Southbank", "sublocality used as suburb");
  assert(parsed?.estate === null, "premise name is not an estate");
});

Deno.test("parse: a non-Australian result is flagged and council is not the suburb", () => {
  const parsed = parseAddressComponents([
    component("10", ["street_number"]),
    component("Queen Street", ["route"]),
    component("Auckland", ["locality"]),
    component("New Zealand", ["country"], "NZ"),
  ]);
  assert(parsed?.inAustralia === false, "NZ is not Australia");

  const councilOnly = parseAddressComponents([
    component("1", ["street_number"]),
    component("Main Road", ["route"]),
    component("Casey", ["administrative_area_level_2"]),
    component("Australia", ["country"], "AU"),
  ]);
  assert(councilOnly?.suburb === "", "LGA is not a suburb");
});

function jwt(sub: string, expSecondsFromNow = 3600): string {
  const enc = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
  return `${enc({ alg: "none", typ: "JWT" })}.${enc({ sub, exp: Math.floor(Date.now() / 1000) + expSecondsFromNow })}.sig`;
}

const TOKEN = "11111111-1111-4111-8111-111111111111";
const USER = "22222222-2222-4222-8222-222222222222";

function post(body: unknown, authorization?: string): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  return new Request("https://example.test/address-suggest", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

Deno.test("callerSub reads a bearer sub and rejects an expired token", () => {
  const req = new Request("https://example.test/", { headers: { authorization: `Bearer ${jwt(USER)}` } });
  assert(callerSub(req) === USER, "sub");
  const old = new Request("https://example.test/", { headers: { authorization: `Bearer ${jwt(USER, -600)}` } });
  assert(callerSub(old) === "", "expired");
  assert(callerSub(new Request("https://example.test/")) === "", "missing");
});

Deno.test("no API key: configured false, Google is not called", async () => {
  Deno.env.delete("GOOGLE_PLACES_API_KEY");
  resetRateLimits();
  let called = 0;
  const orig = globalThis.fetch;
  globalThis.fetch = (() => {
    called++;
    return Promise.reject(new Error("should not fetch"));
  }) as typeof fetch;
  try {
    const res = await handleAddressSuggest(post({ action: "autocomplete", input: "12 Wattle", sessionToken: TOKEN }));
    eq(res.status, 200, "status");
    eq(await res.json(), { configured: false, suggestions: [] }, "body");
    assert(called === 0, "no outbound call");
  } finally {
    globalThis.fetch = orig;
  }
});

Deno.test("autocomplete sends an Australia-only Places request with the session token", async () => {
  Deno.env.set("GOOGLE_PLACES_API_KEY", "test-key-not-real");
  resetRateLimits();
  const seen: { url: string; init: RequestInit }[] = [];
  const orig = globalThis.fetch;
  globalThis.fetch = (async (url: RequestInfo | URL, init?: RequestInit) => {
    seen.push({ url: String(url), init: init ?? {} });
    const headers = new Headers(init?.headers);
    assert(headers.get("X-Goog-Api-Key") === "test-key-not-real", "server key header");
    return new Response(JSON.stringify({
      suggestions: [
        {
          placePrediction: {
            placeId: "ChIJexampleplace",
            types: ["street_address", "geocode"],
            structuredFormat: {
              mainText: { text: "12 Wattle Grove" },
              secondaryText: { text: "Clyde North VIC, Australia" },
            },
          },
        },
        {
          placePrediction: {
            placeId: "ChIJcafeexample1",
            types: ["cafe", "establishment"],
            text: { text: "Wattle Cafe" },
          },
        },
      ],
    }), { status: 200, headers: { "content-type": "application/json" } });
  }) as typeof fetch;
  try {
    const res = await handleAddressSuggest(post(
      { action: "autocomplete", input: "  12   watt  ", sessionToken: TOKEN, latitude: -37.8 },
      `Bearer ${jwt(USER)}`,
    ));
    eq(res.status, 200, "status");
    const body = await res.json();
    eq(body, {
      configured: true,
      suggestions: [{ placeId: "ChIJexampleplace", mainText: "12 Wattle Grove", secondaryText: "Clyde North VIC, Australia" }],
    }, "suggestions drop businesses");
    assert(seen.length === 1, "one google call");
    assert(seen[0].url.endsWith("/places:autocomplete"), "autocomplete url");
    const sent = JSON.parse(String(seen[0].init.body));
    eq(sent.input, "12 watt", "trimmed input");
    eq(sent.includedRegionCodes, ["au"], "australia only");
    eq(sent.sessionToken, TOKEN, "session token");
    eq(sent.regionCode, "au", "region");
    assert(sent.locationBias?.rectangle?.low?.latitude === -44, "fixed AU bias");
    assert(!("latitude" in sent), "client location is not forwarded");
    assert(!("origin" in sent), "no origin / GPS");
    const mask = new Headers(seen[0].init.headers).get("X-Goog-FieldMask") ?? "";
    assert(mask.includes("placeId") && !mask.includes("location"), "field mask has no coordinates");
  } finally {
    globalThis.fetch = orig;
    Deno.env.delete("GOOGLE_PLACES_API_KEY");
  }
});

Deno.test("details uses the same session token and returns estate only from neighborhood", async () => {
  Deno.env.set("GOOGLE_PLACES_API_KEY", "test-key-not-real");
  resetRateLimits();
  const orig = globalThis.fetch;
  let url = "";
  let mask = "";
  globalThis.fetch = (async (u: RequestInfo | URL, init?: RequestInit) => {
    url = String(u);
    mask = new Headers(init?.headers).get("X-Goog-FieldMask") ?? "";
    return new Response(JSON.stringify({
      addressComponents: [
        component("4", ["street_number"]),
        component("Banksia Street", ["route"]),
        component("Clyde North", ["locality"]),
        component("Meridian Estate", ["neighborhood"]),
        component("3978", ["postal_code"]),
        component("Australia", ["country"], "AU"),
      ],
    }), { status: 200 });
  }) as typeof fetch;
  try {
    const res = await handleAddressSuggest(post(
      { action: "details", placeId: "ChIJexampleplace", sessionToken: TOKEN },
      `Bearer ${jwt("33333333-3333-4333-8333-333333333333")}`,
    ));
    const body = await res.json();
    eq(body.address, {
      streetNumber: "4",
      streetName: "Banksia Street",
      suburb: "Clyde North",
      estate: "Meridian Estate",
    }, "filled address");
    assert(url.includes("/places/ChIJexampleplace?"), "place url");
    assert(url.includes(`sessionToken=${TOKEN}`), "session token on details");
    assert(mask === "addressComponents", "details asks only for address components");
    assert(!url.includes("fields=location"), "no location field");
  } finally {
    globalThis.fetch = orig;
    Deno.env.delete("GOOGLE_PLACES_API_KEY");
  }
});

Deno.test("unsigned callers and a missing session are rejected without calling Google", async () => {
  Deno.env.set("GOOGLE_PLACES_API_KEY", "test-key-not-real");
  resetRateLimits();
  let called = 0;
  const orig = globalThis.fetch;
  globalThis.fetch = (() => {
    called++;
    return Promise.resolve(new Response("{}", { status: 200 }));
  }) as typeof fetch;
  try {
    const anon = await handleAddressSuggest(post({ action: "autocomplete", input: "12 Wattle Grove", sessionToken: TOKEN }));
    eq(anon.status, 401, "anon");
    const bad = await handleAddressSuggest(post(
      { action: "autocomplete", input: "12 Wattle Grove", sessionToken: "not-a-uuid" },
      `Bearer ${jwt(USER)}`,
    ));
    eq(bad.status, 400, "bad token");
    assert(called === 0, "no google call");
  } finally {
    globalThis.fetch = orig;
    Deno.env.delete("GOOGLE_PLACES_API_KEY");
  }
});

Deno.test("rate limit stops a burst before it reaches Google", async () => {
  Deno.env.set("GOOGLE_PLACES_API_KEY", "test-key-not-real");
  resetRateLimits();
  let called = 0;
  const orig = globalThis.fetch;
  globalThis.fetch = (async () => {
    called++;
    return new Response(JSON.stringify({ suggestions: [] }), { status: 200 });
  }) as typeof fetch;
  try {
    const sub = "44444444-4444-4444-8444-444444444444";
    let limited = 0;
    for (let i = 0; i < 14; i++) {
      const res = await handleAddressSuggest(post(
        { action: "autocomplete", input: "12 Wattle Grove", sessionToken: TOKEN },
        `Bearer ${jwt(sub)}`,
      ));
      const body = await res.json();
      if (body.limited) limited++;
    }
    assert(called === 12, `expected 12 google calls, got ${called}`);
    assert(limited === 2, `expected 2 limited responses, got ${limited}`);
  } finally {
    globalThis.fetch = orig;
    Deno.env.delete("GOOGLE_PLACES_API_KEY");
  }
});
