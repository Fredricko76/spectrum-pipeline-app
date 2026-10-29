// website-enquiry (v2) — receives enquiries from websites, Google Ads lead forms
// and Meta Lead Ads (via Zapier/Make) and creates a New Enquiry client in the
// Spectrum Sales Pipeline, routed by key via public.lead_sources.
//
// Endpoint: POST https://qjkmkmmrgtoaocygymqo.supabase.co/functions/v1/website-enquiry?key=<site_key>
// Key can also be sent as an "x-site-key" header, or (Google) as "google_key" in the body.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const FIELD_ALIASES: Record<string, string[]> = {
  first_name: ["first_name", "firstname", "first", "name_first"],
  last_name: ["last_name", "lastname", "surname", "last", "name_last"],
  full_name: ["full_name", "name", "fullname"],
  email: ["email", "email_address"],
  phone: ["phone", "phone_number", "mobile"],
  interested_in: ["interested_in", "interest", "build_type"],
  build_location: [
    "build_location",
    "location",
    "where_to_build",
    "suburb",
    "city",
    "postal_code",
    "postcode",
  ],
  journey_stage: ["journey_stage", "stage_of_journey", "building_stage"],
  has_land: ["has_land", "land", "own_land"],
  comments: ["comments", "message", "comment", "notes"],
  lead_id: ["lead_id", "leadgen_id", "external_lead_id"],
  campaign: ["campaign", "campaign_name", "ad_name", "form_name"],
  honeypot: ["website_url", "hp", "_hp"],
};

const BUILD_TYPE_MAP: Record<string, string> = {
  "new home - own plan": "Custom Plans",
  "new home - ellari homes plan": "Standard Plans",
  "knockdown & rebuild": "Knockdown Rebuild",
  "knockdown and rebuild": "Knockdown Rebuild",
  "knockdown rebuild": "Knockdown Rebuild",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-site-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

const clean = (v: unknown, max = 500) =>
  typeof v === "string" || typeof v === "number" ? String(v).replace(/\s+/g, " ").trim().slice(0, max) : "";

function pick(body: Record<string, unknown>, field: string, max = 500): string {
  const lower: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(body)) lower[k.toLowerCase()] = v;
  for (const alias of FIELD_ALIASES[field]) {
    const v = clean(lower[alias], max);
    if (v) return v;
  }
  return "";
}

function auPhone(raw: string): string {
  const digits = raw.replace(/[^\d+]/g, "");
  if (/^\+?61\d{9}$/.test(digits)) return "0" + digits.replace(/^\+?61/, "");
  return raw;
}

function todayIn(tz: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(new Date());
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  const type = req.headers.get("content-type") ?? "";
  if (type.includes("application/json")) return await req.json();
  const form = await req.formData();
  const out: Record<string, unknown> = {};
  form.forEach((v, k) => (out[k] = typeof v === "string" ? v : ""));
  return out;
}

const GOOGLE_COLUMNS: Record<string, string> = {
  FULL_NAME: "full_name",
  FIRST_NAME: "first_name",
  LAST_NAME: "last_name",
  EMAIL: "email",
  PHONE_NUMBER: "phone",
  POSTAL_CODE: "postal_code",
  CITY: "city",
};
function flattenGoogle(body: Record<string, unknown>) {
  const out: Record<string, unknown> = { lead_id: body.lead_id };
  const extras: string[] = [];
  const cols = Array.isArray(body.user_column_data) ? body.user_column_data : [];
  for (const c of cols as Array<Record<string, unknown>>) {
    const id = clean(c.column_id, 100).toUpperCase();
    const val = clean(c.string_value, 1000);
    if (!val) continue;
    const mapped = GOOGLE_COLUMNS[id];
    if (mapped) out[mapped] = val;
    else extras.push(`${clean(c.column_name, 100) || id}: ${val}`);
  }
  if (body.campaign_id) extras.push(`Google campaign ID: ${clean(body.campaign_id)}`);
  if (body.form_id) extras.push(`Google form ID: ${clean(body.form_id)}`);
  out.comments = extras.join("\n");
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { ok: false, error: "POST only" });

  let body: Record<string, unknown>;
  try {
    body = await readBody(req);
  } catch {
    return json(400, { ok: false, error: "Unreadable body" });
  }

  const url = new URL(req.url);
  const isGoogle = Array.isArray(body.user_column_data);
  const key = req.headers.get("x-site-key") ?? url.searchParams.get("key") ??
    (isGoogle ? clean(body.google_key, 200) : "") ?? "";
  if (!key) return json(401, { ok: false, error: "Missing site key" });

  const { data: source } = await supabase
    .from("lead_sources")
    .select("id, label, company_id, default_owner_id, timezone, active, channel")
    .eq("site_key", key)
    .maybeSingle();
  if (!source || !source.active) return json(401, { ok: false, error: "Invalid site key" });

  if (isGoogle && body.google_key && clean(body.google_key, 200) !== key) {
    return json(401, { ok: false, error: "Invalid google_key" });
  }
  if (isGoogle && (body.is_test === true || body.is_test === "true")) {
    return json(200, {});
  }

  const data = isGoogle ? flattenGoogle(body) : body;

  if (pick(data, "honeypot")) return json(200, { ok: true });

  let first = pick(data, "first_name", 100);
  let last = pick(data, "last_name", 100);
  if (!first && !last) {
    const full = pick(data, "full_name", 200).split(" ");
    first = full.shift() ?? "";
    last = full.join(" ");
  }
  const email = pick(data, "email", 200).toLowerCase();
  const phone = auPhone(pick(data, "phone", 40));
  const interested = pick(data, "interested_in", 100);
  const location = pick(data, "build_location", 200);
  const journey = pick(data, "journey_stage", 100);
  const land = pick(data, "has_land", 20);
  const comments = pick(data, "comments", 3000);
  const campaign = pick(data, "campaign", 200);
  const leadId = pick(data, "lead_id", 200);

  if (!first && !last) return json(400, { ok: false, error: "Name required" });
  if (!email && !phone) return json(400, { ok: false, error: "Email or phone required" });

  const channel: string = source.channel ?? "Website";
  const enquiryDate = todayIn(source.timezone);
  const note = [
    `${channel} enquiry (${source.label}) — ${enquiryDate}`,
    campaign && `Campaign: ${campaign}`,
    interested && `Interested in: ${interested}`,
    location && `Where to build: ${location}`,
    journey && `Stage of journey: ${journey}`,
    land && `Has land: ${land}`,
    comments && `Comments: ${comments}`,
  ].filter(Boolean).join("\n");

  if (leadId) {
    const { data: seen } = await supabase
      .from("clients")
      .select("id")
      .eq("company_id", source.company_id)
      .eq("external_lead_id", `${channel}:${leadId}`)
      .maybeSingle();
    if (seen) return json(200, isGoogle ? {} : { ok: true, duplicate: true });
  }

  const digits = phone.replace(/\D/g, "");
  const orFilters = [
    email && `email.ilike.${email}`,
    digits.length >= 8 && `phone.ilike.%${digits.slice(-8)}%`,
  ].filter(Boolean).join(",");

  if (orFilters) {
    const { data: existing } = await supabase
      .from("clients")
      .select("id, notes")
      .eq("company_id", source.company_id)
      .or(orFilters)
      .limit(1)
      .maybeSingle();

    if (existing) {
      const merged = [existing.notes, `--- Repeat ${note}`].filter(Boolean).join("\n\n");
      const { error } = await supabase
        .from("clients")
        .update({ notes: merged })
        .eq("id", existing.id)
        .eq("company_id", source.company_id);
      if (error) {
        console.error("update failed", error);
        return json(500, { ok: false, error: "Could not save enquiry" });
      }
      return json(200, isGoogle ? {} : { ok: true, duplicate: true });
    }
  }

  const { error } = await supabase.from("clients").insert({
    company_id: source.company_id,
    owner_id: source.default_owner_id,
    created_by: source.default_owner_id,
    first_name: first,
    surname: last,
    email: email || null,
    phone: phone || null,
    enquiry_date: enquiryDate,
    build_type: BUILD_TYPE_MAP[interested.toLowerCase()] ?? null,
    stage: "New Enquiry",
    lead_source: channel,
    external_lead_id: leadId ? `${channel}:${leadId}` : null,
    notes: note,
  });

  if (error) {
    if ((error as { code?: string }).code === "23505") {
      return json(200, isGoogle ? {} : { ok: true, duplicate: true });
    }
    console.error("insert failed", error);
    return json(500, { ok: false, error: "Could not save enquiry" });
  }
  return json(200, isGoogle ? {} : { ok: true });
});
