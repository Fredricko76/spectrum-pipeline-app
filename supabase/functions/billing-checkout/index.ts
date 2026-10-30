// POST /functions/v1/billing-checkout   body: { "plan": "starter" | "team" | "network" }
// Returns { url } for a Stripe Checkout Session (subscription mode).
// A card is always required (payment_method_collection 'always').
// First subscription for a company: 14-day free trial - the card is saved but not charged until the
// trial ends. Stripe's default trial end behaviour then invoices the saved card; if that payment fails
// the subscription goes past_due and the normal 7-day grace period applies.
import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import {
  adminClient,
  APP_TAG,
  appUrl,
  callerCompany,
  HttpError,
  json,
  PLAN_LOOKUP_KEYS,
  type PlanKey,
  serve,
  stripe,
  TRIAL_DAYS,
} from "../_shared/billing.ts";

const LIVE_STATUSES = new Set(["trialing", "active", "past_due", "unpaid", "paused", "incomplete"]);

serve(async (req) => {
  const body = await req.json().catch(() => ({})) as { plan?: string };
  const plan = body.plan as PlanKey;
  if (!plan || !(plan in PLAN_LOOKUP_KEYS)) throw new HttpError(400, "Choose Starter, Team or Network.");

  const me = await callerCompany(req);
  if (me.isComped) {
    throw new HttpError(409, "Your company is on a complimentary plan - there is nothing to pay.");
  }
  if (!me.canManage) throw new HttpError(403, "Only an owner or admin can choose the plan.");
  if (me.stripeSubscriptionId && LIVE_STATUSES.has(me.status)) {
    // Already subscribed: plan changes and card updates happen in the Customer Portal.
    return json(req, 409, {
      error: "You already have a subscription. Use Billing to change plan.",
      portal: true,
    });
  }

  const s = stripe();
  const prices = await s.prices.list({ lookup_keys: [PLAN_LOOKUP_KEYS[plan]], active: true, limit: 1 });
  const price = prices.data[0];
  if (!price) throw new Error(`No active Stripe price for lookup key ${PLAN_LOOKUP_KEYS[plan]}`);

  const meta = { company_id: me.companyId, app: APP_TAG };

  // One Stripe customer per company. The idempotency key stops double-clicks creating two.
  let customerId = me.stripeCustomerId;
  if (!customerId) {
    const customer = await s.customers.create(
      { name: me.companyName, email: me.email ?? undefined, metadata: meta },
      { idempotencyKey: `pipeline-customer-${me.companyId}` },
    );
    customerId = customer.id;
    const { error } = await adminClient().from("companies")
      .update({ stripe_customer_id: customerId, billing_updated_at: new Date().toISOString() })
      .eq("id", me.companyId).is("stripe_customer_id", null);
    if (error) throw new Error(`Could not save customer id: ${error.message}`);
  }

  // Ask Stripe too: the webhook may not have recorded an earlier Checkout yet (or failed), and
  // the database alone would then let the company start a second subscription and trial.
  const existing = await s.subscriptions.list({ customer: customerId, status: "all", limit: 20 });
  const ours = existing.data.filter((x) => x.metadata?.app === APP_TAG);
  if (ours.some((x) => LIVE_STATUSES.has(x.status))) {
    return json(req, 409, {
      error: "You already have a subscription. Use Billing to change plan.",
      portal: true,
    });
  }

  // A company gets one free trial, ever.
  const trialEligible = !me.stripeSubscriptionId && !me.trialEndsAt && ours.length === 0;

  const session = await s.checkout.sessions.create({
    mode: "subscription",
    customer: customerId,
    client_reference_id: me.companyId,
    metadata: meta,
    line_items: [{ price: price.id, quantity: 1 }],
    payment_method_collection: "always",
    subscription_data: {
      metadata: meta,
      ...(trialEligible ? { trial_period_days: TRIAL_DAYS } : {}),
    },
    automatic_tax: { enabled: true },
    tax_id_collection: { enabled: true }, // ABN
    customer_update: { address: "auto", name: "auto" },
    billing_address_collection: "required",
    allow_promotion_codes: true,
    success_url: `${appUrl()}/?billing=success&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${appUrl()}/?billing=cancel`,
  });

  return json(req, 200, { url: session.url });
});
