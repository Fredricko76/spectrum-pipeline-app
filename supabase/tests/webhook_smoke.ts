// Local smoke test for stripe-webhook (signature checks + ignore paths). No network to Stripe.
// Terminal 1: STRIPE_SECRET_KEY=sk_test_dummy STRIPE_WEBHOOK_SECRET=whsec_local_dummy APP_URL=http://localhost \
//   SUPABASE_URL=http://127.0.0.1:9 SUPABASE_SERVICE_ROLE_KEY=dummy SUPABASE_ANON_KEY=dummy deno run -A functions/stripe-webhook/index.ts
// Terminal 2: deno run -A tests/webhook_smoke.ts
import Stripe from "npm:stripe@23.0.1";
const s = new Stripe("sk_test_dummy_local");
const url = "http://localhost:8000/";
const post = async (body: string, sig: string | null) => {
  const r = await fetch(url, { method: "POST", body, headers: sig ? { "stripe-signature": sig } : {} });
  return `${r.status} ${await r.text()}`;
};
const ev = (type: string, obj: unknown) => JSON.stringify({ id: "evt_local_" + type, object: "event", type, data: { object: obj } });
const sign = async (p: string) => await s.webhooks.generateTestHeaderStringAsync({ payload: p, secret: "whsec_local_dummy" });
console.log("no signature      ->", await post(ev("invoice.paid", {}), null));
console.log("bad signature     ->", await post(ev("invoice.paid", {}), "t=1,v1=deadbeef"));
const p1 = ev("charge.succeeded", { id: "ch_1" });
console.log("unhandled type    ->", await post(p1, await sign(p1)));
const p2 = ev("checkout.session.completed", { id: "cs_1", subscription: null, metadata: {} });
console.log("no subscription   ->", await post(p2, await sign(p2)));
