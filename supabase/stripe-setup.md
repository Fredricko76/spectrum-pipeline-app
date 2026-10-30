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

- **Trial policy**: Checkout always collects a card (`payment_method_collection: always`). A company's
  first subscription gets a 14-day free trial; the card is charged when the trial ends unless the
  subscription is cancelled first. A failed first charge follows the normal past_due / 7-day grace path.
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
| Trial (card required) | Sign up -> Choose plan -> Checkout with `4242 4242 4242 4242` | `trialing`, banner "14 days left", full access, A$0 charged today |
| Trial ends | Test clock: advance 15 days | First invoice paid -> `active`, banner gone |
| Trial ends, card fails | Checkout with `4000 0000 0000 0341`, advance 15 days | `past_due`, "update card" banner, 7 days' grace, then read-only |
| Cancel during trial | Portal -> cancel | Nothing charged; `canceled` at trial end -> read-only |
| Renewal fails | Card `4000 0000 0000 0341`, advance past period end | `past_due`, "update card" banner, full access for 7 days, then read-only |
| Recovery | Portal -> update card to 4242 | `invoice.paid` -> `active`, grace cleared |
| 3-D Secure | `4000 0025 0000 3155` | Checkout completes after challenge |
| Declined | `4000 0000 0000 9995` | Checkout shows error; nothing changes |
| Upgrade / downgrade | Portal -> switch Starter <-> Team | `plan`/`seat_limit` follow the price metadata |
| Cancel | Portal -> cancel | `cancel_at_period_end`, then `canceled` -> read-only |
| Duplicate event | Dashboard -> resend an event | `{duplicate:true}`, no change |
| Untagged event | Create a subscription for another product | `{ignored: ...}`, no change |
| Comped company | Any Hotondo company | No billing UI, never changed by the webhook |
| Admin-created company | Platform panel › Set up a new company (box unticked) | Starts read-only with the plan picker, like a sign-up |
| Comp toggle | Platform panel › Companies › Billing › tick Complimentary (free) | Full access, no billing UI; refused while a Stripe subscription is live (cancel it first) |
| Enquiry to read-only company | POST website-enquiry with that company's site key | HTTP 200 `{"ok":true,"saved":false}`, no lead, log line `enquiry_skipped_read_only` |

## Test-mode objects (created 2026-10-30, account acct_1POqw5S3hxQFvThd, livemode=false)

| Plan | Product | Price (lookup key) | AUD ex GST |
|---|---|---|---|
| Starter (3 seats) | prod_VX6FpiNgwdnFQE | price_1UW22qS3hxQFvThdwrwY8T91 (`pipeline_starter_monthly`) | 149.00/mo |
| Team (10 seats) | prod_VX6FXLs6MYsr7v | price_1UW22sS3hxQFvThdozmt2fl9 (`pipeline_team_monthly`) | 349.00/mo |
| Network (25 seats) | prod_VX6FifliOhK29x | price_1UW22vS3hxQFvThdr8dmJXgN (`pipeline_network_monthly`) | 799.00/mo |

Customer Portal configuration: `bpc_1UW23JS3hxQFvThdv3ugAPBY` -> `STRIPE_PORTAL_CONFIG_ID` (test).
It is the test-mode *default* configuration only because it is the only one there; in live mode
the script's new configuration is not the default, and the functions always pass it explicitly.

AU GST registration (test): `taxreg_1UW2OeS3hxQFvThdTxit9l1t` - verified 10% GST on an exclusive price.
Webhook endpoint (test): `we_1UW2O9S3hxQFvThdk30rk1L3` ->
`https://wwdhiailerkmwpnuqpvm.supabase.co/functions/v1/stripe-webhook` (Supabase branch billing-test).
Its signing secret is shown only in the Dashboard (Developers > Webhooks > endpoint > Reveal) and must be
set as `STRIPE_WEBHOOK_SECRET` on the branch. Smart Retries / "mark unpaid" are Dashboard-only settings.

## billing-test environment
- Supabase branch `billing-test` (`wwdhiailerkmwpnuqpvm`): all 58 production migrations + `stripe_billing`,
  fake seed data only. Function secrets needed there: `STRIPE_SECRET_KEY` (test key) and `STRIPE_WEBHOOK_SECRET`.
  `APP_URL` and `STRIPE_PORTAL_CONFIG_ID` default from `TEST_PROJECT_DEFAULTS` in `_shared/billing.ts`.
- Netlify deploy previews / branch deploys point at the branch (`scripts/preview-supabase.sh`).

## Go-live checks (before applying the migration to production)

- **service_role grant on `stripe_events`.** The migration now grants `select, insert, update, delete` to
  `service_role` explicitly (the undo revokes it). Why: on the billing-test branch the default privileges for
  tables created by `postgres` give `service_role` no table rights, so the webhook failed with
  `permission denied for table stripe_events` (2026-10-30 12:31 AEDT). Read-only check of production
  (qjkmkmmrgtoaocygymqo, 2026-10-30 12:40 AEDT): its default privileges for `postgres` tables do grant
  `service_role` (and anon/authenticated, which the migration revokes) full rights, and no existing public
  table is missing service_role rights - so production would have worked, and the explicit grant makes it
  certain. After go-live, confirm: `select has_table_privilege('service_role','public.stripe_events','select,insert,update,delete');`
  returns true and `has_table_privilege('anon', ...)` / `('authenticated', ...)` return false.
- Every other object the functions use (`companies`, `company_access`, `company_can_write`, `my_billing`)
  already had the needed grants on the branch.
- **Free (comped) companies are a deliberate choice.** Only the 5 existing companies are comped by the migration.
  Companies Fred creates in the platform panel start with no plan (read-only) unless he ticks
  *Complimentary (free)* there (`platform_set_company_comped`, platform admins only, audit-logged).
- **website-enquiry must be deployed to production at go-live, after the migration.** The new version skips leads
  for read-only companies (200 `{"ok":true,"saved":false}`, logged). Until then production keeps the old function.
  The new code is safe either way: if `company_access()` doesn't exist it saves the lead as before.
  Before go-live, check that every company with an active `lead_sources` row is comped or on a plan, or its
  leads will stop being saved.
