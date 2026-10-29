// Shared helpers for the billing edge functions.
// Env (set as Supabase function secrets, never in the repo):
//   STRIPE_SECRET_KEY        sk_test_... / rk_test_... (restricted key recommended)
//   STRIPE_WEBHOOK_SECRET    whsec_... for the stripe-webhook endpoint
//   APP_URL                  e.g. https://spectrumsalesonline.net (no trailing slash)
//   STRIPE_PORTAL_CONFIG_ID  bpc_... dedicated Customer Portal configuration
// APP_URL and STRIPE_PORTAL_CONFIG_ID fall back to TEST_PROJECT_DEFAULTS on known test projects.
//   ALLOWED_ORIGINS          optional, comma-separated extra CORS origins (e.g. a deploy preview)
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
import Stripe from "npm:stripe@23.0.1";
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

export const APP_TAG = "spectrum-pipeline";

export const PLAN_LOOKUP_KEYS = {
  starter: "pipeline_starter_monthly",
  team: "pipeline_team_monthly",
  network: "pipeline_network_monthly",
} as const;
export type PlanKey = keyof typeof PLAN_LOOKUP_KEYS;

export const TRIAL_DAYS = 14;

export const PRODUCTION_PROJECT_REF = "qjkmkmmrgtoaocygymqo";

/**
 * NON-SECRET defaults for known test projects, used only when the env var is not set.
 * Production has no defaults: every value must come from its function secrets.
 * Never put a Stripe secret key or webhook signing secret here.
 */
const TEST_PROJECT_DEFAULTS: Record<string, Record<string, string>> = {
  // Supabase development branch "billing-test" + Netlify deploy preview of PR #4 + Stripe TEST mode
  wwdhiailerkmwpnuqpvm: {
    APP_URL: "https://deploy-preview-4--spectrum-pipeline-app.netlify.app",
    STRIPE_PORTAL_CONFIG_ID: "bpc_1UW23JS3hxQFvThdv3ugAPBY",
  },
};

export function projectRef(): string {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  return url.match(/^https:\/\/([a-z0-9]+)\.supabase\.co/)?.[1] ?? "";
}

export function env(name: string): string {
  const v = Deno.env.get(name) || TEST_PROJECT_DEFAULTS[projectRef()]?.[name];
  if (!v) throw new Error(`Missing env var ${name}`);
  return v;
}

export function appUrl(): string {
  return env("APP_URL").replace(/\/+$/, "");
}

let _stripe: Stripe | null = null;
export function stripe(): Stripe {
  if (!_stripe) {
    const key = env("STRIPE_SECRET_KEY");
    // a live key may only ever be used by the production project
    if (/^(sk|rk)_live_/.test(key) && projectRef() !== PRODUCTION_PROJECT_REF) {
      throw new Error("Refusing to use a live Stripe key outside the production project");
    }
    _stripe = new Stripe(key, {
      httpClient: Stripe.createFetchHttpClient(),
      appInfo: { name: "spectrum-pipeline-billing" },
    });
  }
  return _stripe;
}

/** Service-role client: bypasses RLS. Only used server-side for billing columns. */
export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

// ---------------------------------------------------------------- HTTP helpers
function allowedOrigins(): string[] {
  const extra = (Deno.env.get("ALLOWED_ORIGINS") ?? "")
    .split(",").map((s) => s.trim()).filter(Boolean);
  return [appUrl(), ...extra];
}

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allow = allowedOrigins().includes(origin) ? origin : appUrl();
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function json(req: Request, status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

// ---------------------------------------------------------------- caller context
export interface CallerCompany {
  userId: string;
  email: string | null;
  companyId: string;
  companyName: string;
  canManage: boolean;
  isComped: boolean;
  status: string;
  stripeCustomerId: string | null;
  stripeSubscriptionId: string | null;
  trialEndsAt: string | null;
}

/**
 * Resolves the signed-in user and the company they are currently acting as, using the
 * same database functions the app uses (auth_company_id / is_manager via my_billing()).
 */
export async function callerCompany(req: Request): Promise<CallerCompany> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) throw new HttpError(401, "Sign in first.");

  const userClient = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: uErr } = await userClient.auth.getUser(
    authHeader.slice("Bearer ".length),
  );
  if (uErr || !user) throw new HttpError(401, "Your session has expired. Sign in again.");

  const { data: bill, error: bErr } = await userClient.rpc("my_billing");
  const row = Array.isArray(bill) ? bill[0] : bill;
  if (bErr || !row) throw new HttpError(403, "This account does not belong to a company.");

  const { data: co, error: cErr } = await adminClient()
    .from("companies")
    .select(
      "id, name, stripe_customer_id, stripe_subscription_id, trial_ends_at, is_comped, subscription_status",
    )
    .eq("id", row.company_id)
    .single();
  if (cErr || !co) throw new HttpError(404, "Company not found.");

  return {
    userId: user.id,
    email: user.email ?? null,
    companyId: co.id,
    companyName: co.name,
    canManage: !!row.can_manage,
    isComped: !!co.is_comped,
    status: co.subscription_status,
    stripeCustomerId: co.stripe_customer_id,
    stripeSubscriptionId: co.stripe_subscription_id,
    trialEndsAt: co.trial_ends_at,
  };
}

/** Wraps a handler with CORS preflight + uniform error responses. */
export function serve(handler: (req: Request) => Promise<Response>) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
    if (req.method !== "POST") return json(req, 405, { error: "Method not allowed" });
    try {
      return await handler(req);
    } catch (e) {
      if (e instanceof HttpError) return json(req, e.status, { error: e.message });
      console.error("billing error", e instanceof Error ? e.message : e);
      return json(req, 500, { error: "Billing is unavailable right now. Please try again." });
    }
  });
}
