# Stripe billing setup (sandbox first)

Everything here is for a Stripe **sandbox / test mode**. Do not run it against the live
Spectrum Coach account until the sandbox run has been signed off.

## 1. Catalogue + portal (script)

```bash
export STRIPE_SECRET_KEY=sk_test_...          # or a restricted rk_test_ key; never commit it
APP_URL=https://spectrumsalesonline.net ./supabase/stripe-setup.sh
```

Creates (re-runnable; it reuses existing lookup keys):

| Product | Price (AUD, monthly, GST exclusive) | lookup_key | metadata |
|---|---|---|---|
| Spectrum Pipeline Starter | 149.00 | `pipeline_starter_monthly` | `plan=starter`, `seat_limit=3` |
| Spectrum Pipeline Team | 349.00 | `pipeline_team_monthly` | `plan=team`, `seat_limit=10` |
| Spectrum Pipeline Network | 799.00 | `pipeline_network_monthly` | `plan=network`, `seat_limit=25` |

All products use tax code `txcd_10103001` (SaaS, business use) and `metadata.app=spectrum-pipeline`.
It also creates a dedicated Customer Portal configuration (only these 3 prices; card update,
invoices, name/email/address/ABN updates, cancel at period end, plan switch with proration),
and prints its `bpc_...` id.

Custom Network quotes: create an extra price on the Network product in the Dashboard with
`metadata.plan=network` and `metadata.seat_limit=<n>`; the webhook picks the seats up from it.

## 2. Dashboard settings (sandbox)

- **Tax**: Stripe Tax on, AU registration (the live account already has both). Checkout uses
  `automatic_tax` and collects the ABN (`tax_id_collection`).
- **Billing -> Revenue recovery -> Retries**: Smart Retries; after all retries fail,
  **mark the subscription as unpaid** (the app gives 7 days grace from the first failure, then read-only).
- **Billing -> Subscriptions -> Emails**: send trial-ending reminders (7 days before) and
  failed-payment emails; enable "Link to a Stripe-hosted page" so customers can fix cards.
- **Webhook endpoint**: `https://<project-ref>.supabase.co/functions/v1/stripe-webhook`, events:
  `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `customer.subscription.paused`, `customer.subscription.resumed`,
  `customer.subscription.trial_will_end`, `invoice.paid`, `invoice.payment_failed`.
  API version `2026-09-30.endive`. Copy its signing secret straight into the secret below.
- **Live only, later**: the existing live endpoint
  `portal.spectrumcoachmasteringsales.com/api/stripe/webhook` receives *all* subscription events on
  the account. Before going live, make it ignore events whose subscription has
  `metadata.app=spectrum-pipeline`.

## 3. Edge function secrets (the Supabase project used for testing - not production yet)

```bash
supabase secrets set --project-ref <test-ref> \
  STRIPE_SECRET_KEY=... STRIPE_WEBHOOK_SECRET=... STRIPE_PORTAL_CONFIG_ID=bpc_... \
  APP_URL=https://<preview-or-app-url>       # optional: ALLOWED_ORIGINS=https://a,https://b
supabase functions deploy billing-checkout billing-portal stripe-webhook --project-ref <test-ref>
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided by Supabase.
Use a restricted key with write access to: Customers, Checkout Sessions, Customer Portal,
Subscriptions (read), Prices (read), Products (read).

## 4. Test plan

| Scenario | How | Expected in app |
|---|---|---|
| Trial without card | Sign up -> Choose plan -> Checkout, skip card | `trialing`, banner "14 days left", full access |
| Trial ends, no card | Test clock: advance 15 days | Subscription `canceled` -> read-only, data visible |
| Trial ends, card added | Portal -> add `4242 4242 4242 4242`, advance clock | `active`, banner gone |
| Renewal fails | Card `4000 0000 0000 0341`, advance past period end | `past_due`, "update card" banner, full access for 7 days, then read-only |
| Recovery | Portal -> update card to 4242 | `invoice.paid` -> `active`, grace cleared |
| 3-D Secure | `4000 0025 0000 3155` | Checkout completes after challenge |
| Declined | `4000 0000 0000 9995` | Checkout shows error; nothing changes |
| Upgrade / downgrade | Portal -> switch Starter <-> Team | `plan`/`seat_limit` follow the price metadata |
| Cancel | Portal -> cancel | `cancel_at_period_end`, then `canceled` -> read-only |
| Duplicate event | Dashboard -> resend an event | `{duplicate:true}`, no change |
| Untagged event | Create a subscription for another product | `{ignored: ...}`, no change |
| Comped company | Any Hotondo company | No billing UI, never changed by the webhook |

## Test-mode objects (created 2026-10-30, account acct_1POqw5S3hxQFvThd, livemode=false)

| Plan | Product | Price (lookup key) | AUD ex GST |
|---|---|---|---|
| Starter (3 seats) | prod_VX6FpiNgwdnFQE | price_1UW22qS3hxQFvThdwrwY8T91 (`pipeline_starter_monthly`) | 149.00/mo |
| Team (10 seats) | prod_VX6FXLs6MYsr7v | price_1UW22sS3hxQFvThdozmt2fl9 (`pipeline_team_monthly`) | 349.00/mo |
| Network (25 seats) | prod_VX6FifliOhK29x | price_1UW22vS3hxQFvThdr8dmJXgN (`pipeline_network_monthly`) | 799.00/mo |

Customer Portal configuration: `bpc_1UW23JS3hxQFvThdv3ugAPBY` -> `STRIPE_PORTAL_CONFIG_ID` (test).
It is the test-mode *default* configuration only because it is the only one there; in live mode
the script's new configuration is not the default, and the functions always pass it explicitly.

Test mode has Stripe Tax active (head office VIC) but **no AU registration yet** - add one
(Dashboard > Tax > Registrations, Australia GST) or Checkout will charge $0 GST.
No webhook endpoint yet: create it once `stripe-webhook` is deployed to a test Supabase project.
