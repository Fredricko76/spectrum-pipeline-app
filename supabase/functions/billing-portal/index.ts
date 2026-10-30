// POST /functions/v1/billing-portal   -> { url } for the Stripe Customer Portal
// (change plan, update card, invoices, cancel at period end) using the dedicated
// portal configuration STRIPE_PORTAL_CONFIG_ID.
import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { appUrl, callerCompany, env, HttpError, json, serve, stripe } from "../_shared/billing.ts";

serve(async (req) => {
  const me = await callerCompany(req);
  if (me.isComped) throw new HttpError(409, "Your company is on a complimentary plan.");
  if (!me.canManage) throw new HttpError(403, "Only an owner or admin can manage billing.");
  if (!me.stripeCustomerId) throw new HttpError(409, "Choose a plan first.");

  const session = await stripe().billingPortal.sessions.create({
    customer: me.stripeCustomerId,
    configuration: env("STRIPE_PORTAL_CONFIG_ID"),
    return_url: `${appUrl()}/?billing=portal`,
  });
  return json(req, 200, { url: session.url });
});
