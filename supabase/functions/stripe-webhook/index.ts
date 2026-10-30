// POST /functions/v1/stripe-webhook   (verify_jwt = false; Stripe signs the request instead)
// Keeps companies.{plan, seat_limit, subscription_status, trial_ends_at, ...} in sync.
// Rules:
//  * signature verified with STRIPE_WEBHOOK_SECRET
//  * events without our company_id/app metadata are ignored (the Stripe account also
//    sells other products and has another webhook endpoint)
//  * idempotent through public.stripe_events
//  * the subscription is re-fetched from Stripe on every event, so event order doesn't matter
//  * comped companies are never touched
import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import Stripe from "npm:stripe@23.0.1";
import { adminClient, APP_TAG, secretEnv, stripe } from "../_shared/billing.ts";

const HANDLED = new Set([
  "checkout.session.completed",
  "customer.subscription.created",
  "customer.subscription.updated",
  "customer.subscription.deleted",
  "customer.subscription.paused",
  "customer.subscription.resumed",
  "customer.subscription.trial_will_end",
  "invoice.paid",
  "invoice.payment_failed",
]);

const PLANS = new Set(["starter", "team", "network"]);

// Stripe's SubtleCrypto provider (sync crypto is unavailable in the edge runtime).
const cryptoProvider = Stripe.createSubtleCryptoProvider();

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

type Meta = Record<string, string> | null | undefined;
const tagged = (m: Meta) => !!m && m.app === APP_TAG && !!m.company_id;
const idOf = (x: unknown): string | null =>
  typeof x === "string"
    ? x
    : (x && typeof x === "object" && "id" in x ? String((x as { id: string }).id) : null);

/** Find the subscription id (and any company tag) an event refers to. */
function subscriptionRef(event: Stripe.Event): { subId: string | null; meta: Meta } {
  // deno-lint-ignore no-explicit-any
  const o = event.data.object as any;
  switch (event.type) {
    case "checkout.session.completed":
      return { subId: idOf(o.subscription), meta: o.metadata };
    case "invoice.paid":
    case "invoice.payment_failed": {
      const det = o.parent?.subscription_details; // API 2025-03-31+
      return {
        subId: idOf(det?.subscription ?? o.subscription),
        meta: det?.metadata ?? o.subscription_details?.metadata,
      };
    }
    default: // customer.subscription.*
      return { subId: o.id ?? null, meta: o.metadata };
  }
}

const ts = (sec: number | null | undefined) => (sec ? new Date(sec * 1000).toISOString() : null);

Deno.serve(async (req) => {
  if (req.method !== "POST") return reply(405, { error: "Method not allowed" });

  const signature = req.headers.get("stripe-signature");
  if (!signature) return reply(400, { error: "Missing signature" });
  const raw = await req.text();

  let whsec: string;
  try {
    whsec = secretEnv("STRIPE_WEBHOOK_SECRET", /^whsec_/, "whsec_...");
  } catch (_e) {
    return reply(500, { error: "Webhook not configured" }); // safe diagnostics already logged
  }

  let event: Stripe.Event;
  try {
    event = await stripe().webhooks.constructEventAsync(
      raw,
      signature,
      whsec,
      undefined,
      cryptoProvider,
    );
  } catch (_e) {
    console.warn("webhook signature check failed");
    return reply(400, { error: "Bad signature" });
  }

  if (!HANDLED.has(event.type)) return reply(200, { ignored: "event type" });

  const { subId, meta } = subscriptionRef(event);
  if (!subId) return reply(200, { ignored: "no subscription" });

  const s = stripe();
  // Re-fetch: the current subscription state is the single source of truth.
  let sub: Stripe.Subscription;
  try {
    sub = await s.subscriptions.retrieve(subId, { expand: ["items.data.price.product"] });
  } catch (e) {
    console.error("subscription fetch failed", event.id, e instanceof Error ? e.message : e);
    return reply(500, { error: "retry" });
  }
  const subMeta = sub.metadata as Meta;
  if (!tagged(subMeta) && !tagged(meta)) return reply(200, { ignored: "not a pipeline subscription" });
  const companyId = (tagged(subMeta) ? subMeta! : meta!).company_id;

  const db = adminClient();

  // ---- idempotency ---------------------------------------------------------------
  const { data: prior } = await db.from("stripe_events").select("processed_at").eq("id", event.id)
    .maybeSingle();
  if (prior?.processed_at) return reply(200, { duplicate: true });
  if (!prior) {
    const { error: insErr } = await db.from("stripe_events")
      .insert({ id: event.id, type: event.type, company_id: companyId });
    if (insErr?.code === "23503") return reply(200, { ignored: "unknown company" }); // company deleted
    if (insErr && insErr.code !== "23505") { // 23505: a parallel delivery got there first
      console.error("stripe_events insert failed", event.id, insErr.message);
      return reply(500, { error: "retry" });
    }
    if (insErr) return reply(200, { duplicate: true });
  }

  const done = async (body: Record<string, unknown>) => {
    await db.from("stripe_events").update({ processed_at: new Date().toISOString() }).eq("id", event.id);
    return reply(200, body);
  };

  // ---- load company ----------------------------------------------------------------
  const { data: co, error: coErr } = await db.from("companies")
    .select("id, is_comped, stripe_customer_id, stripe_subscription_id, subscription_status, past_due_since")
    .eq("id", companyId).maybeSingle();
  if (coErr) return reply(500, { error: "retry" });
  if (!co) return done({ ignored: "unknown company" });
  if (co.is_comped) return done({ ignored: "comped company" });

  const customerId = idOf(sub.customer);
  if (co.stripe_customer_id && co.stripe_customer_id !== customerId) {
    console.warn("customer mismatch; ignoring", event.id, companyId);
    return done({ ignored: "customer mismatch" });
  }
  // An old, finished subscription must not overwrite a newer one.
  const finished = ["canceled", "incomplete_expired"].includes(sub.status);
  if (co.stripe_subscription_id && co.stripe_subscription_id !== sub.id && finished) {
    return done({ ignored: "stale subscription" });
  }

  // ---- map price -> plan + seats ------------------------------------------------------
  const item = sub.items.data[0];
  const price = item?.price;
  const product = price && typeof price.product === "object" ? price.product as Stripe.Product : null;
  const plan = price?.metadata?.plan ?? product?.metadata?.plan;
  const seats = parseInt(price?.metadata?.seat_limit ?? product?.metadata?.seat_limit ?? "", 10);

  // deno-lint-ignore no-explicit-any
  const periodEnd = (item as any)?.current_period_end ?? (sub as any).current_period_end;

  const update: Record<string, unknown> = {
    stripe_customer_id: customerId,
    stripe_subscription_id: sub.id,
    stripe_price_id: price?.id ?? null,
    subscription_status: sub.status,
    trial_ends_at: ts(sub.trial_end),
    current_period_end: ts(periodEnd),
    cancel_at_period_end: !!sub.cancel_at_period_end,
    past_due_since: sub.status === "past_due" ? (co.past_due_since ?? new Date().toISOString()) : null,
    billing_updated_at: new Date().toISOString(),
  };
  if (plan && PLANS.has(plan) && Number.isFinite(seats) && seats > 0) {
    update.plan = plan;
    update.seat_limit = seats; // may drop below seats used: nobody is removed, invites stop
  } else {
    console.warn("price without plan/seat_limit metadata", price?.id);
  }

  const { error: upErr } = await db.from("companies").update(update).eq("id", companyId).eq(
    "is_comped",
    false,
  );
  if (upErr) {
    console.error("company update failed", event.id, upErr.message);
    return reply(500, { error: "retry" });
  }
  return done({ ok: true, status: sub.status });
});
