# Lead connections

Lead connections let a company's owners and admins connect website forms, Meta (Facebook and Instagram) Lead Ads and
Google Ads lead forms to their pipeline. Every enquiry goes to the existing `website-enquiry` edge function and arrives
as a **New Enquiry** client with the right lead source.

Status: **live**. The migration was applied to production on 31 Oct 2026 at 12:58 PM AEDT (recorded as version
`20261031015808` `lead_connections`), and the screen shipped with PR #12. No edge function change was needed.

## What's already live

- Table `public.lead_sources` (id, company_id, channel, label, site_key, active, default_owner_id, timezone, created_at)
  has RLS on and a deny-all policy. Nobody can read keys through the API, so no company can see another company's keys.
- Edge function `website-enquiry` (production v17, `verify_jwt = false`, matches `supabase/functions/website-enquiry`
  in this repo):
  - It finds the company by key. The key can come from the `x-site-key` header, from `?key=` in the link, or (for
    Google) from `google_key` in the body. An unknown or switched-off key gets HTTP 401.
  - It accepts JSON, `multipart/form-data` or `application/x-www-form-urlencoded`. Field names are matched using
    `FIELD_ALIASES` and they aren't case-sensitive. Unknown fields are ignored.
  - Each enquiry needs a name, plus an email or a phone number.
  - If the company is read-only (no active plan and not comped), it returns HTTP 200 `{"ok":true,"saved":false}` and
    saves nothing.
  - Google lead form tests (`is_test: true`) get HTTP 200 and are not saved. There's no test mode for website or
    Zapier/Make posts.

## Migration (applied 31 Oct 2026)

- `supabase/migrations/20261031150000_lead_connections.sql`. It only adds new functions: no table, column or policy
  changes, and `lead_sources` keeps its deny-all policy.
- Undo: `supabase/rollback/20261031150000_lead_connections_undo.sql`. It drops the five functions and keeps every
  `lead_sources` row, so connected forms keep working.

The functions:

| Function | Who | What it does |
|---|---|---|
| `my_lead_sources()` | owner or admin (`is_manager()`) | Lists the caller's own company's connections, including the key. Consultants and other companies get no rows. |
| `lead_source_create(channel, timezone)` | owner or admin, company must be able to write | Creates the key for `Website`, `Meta` or `Google`. It's idempotent: if a key already exists for that channel, it switches it back on and returns it. The default owner is the creator. The timezone is checked against `pg_timezone_names` (default `Australia/Sydney`). |
| `lead_source_regenerate(id)` | owner or admin, own company | Makes a new key. The old one stops working straight away. This is allowed while read-only, so a leaked key can always be killed. |
| `lead_source_update(id, default_owner, active)` | owner or admin, own company | Changes who new leads go to (must be an active member of the company), or switches the connection off or on. |
| `lead_source_new_key()` | internal only | `lk_` plus 48 random hex characters. Not callable by app users. |

- All of them are `SECURITY DEFINER` with `search_path = ''`.
- `anon` can't call any of them.
- Errors: `42501` means not allowed or read-only. `22023` means a bad channel, timezone or owner. `P0002` means not
  found (which includes another company's id).

### Tests

`supabase/tests/run_lead_connections.sh` builds a scratch database on local Postgres 17. It applies the baseline and
the earlier migrations, then this one, and runs `supabase/tests/lead_connections_test.sql` (21 checks):

- keys aren't readable from the table
- create is idempotent per channel, and a bad channel is refused
- the timezone and key format are checked
- the default owner is the creator
- regenerate works, and the owner can be reassigned to members only
- switch off and back on works
- consultants are refused
- other companies are refused
- anon is refused
- a read-only company can't create a key but can regenerate one

The script then runs the undo, checks the schema is identical to before, and re-applies. Last run: 21 PASS, undo OK,
re-apply OK.

## The screen

- **Where:** a **Lead connections** button in the header (owners and admins only), and an **Open lead connections**
  button in the Team & company window.
- **Who:** if a consultant forces the screen open, they get "Only owners and admins can manage lead connections."
- **Tabs:** Website form, Meta Lead Ads and Google Ads. Each tab shows:
  - the link and key, masked by default, with Copy link, Copy key and Show key
  - who new leads go to
  - Turn off / Turn back on
  - Regenerate key, with a warning that the old forms stop working straight away
  - Create connection key, if there isn't one yet
- **Before the migration is applied:** the screen says "Lead connections aren't switched on for your workspace yet" and
  still shows the guides.
- **When the company is read-only:** a light notice says enquiries aren't being saved, with a link to Billing. Create
  is disabled.

### Send a test enquiry

The website function has no dry-run, so the test sends a real, clearly labelled enquiry through the company's own link:

- First name `Test`, surname `Enquiry - delete me`
- Email `test+<timestamp>@example.com`
- Campaign `Connection test`

The screen then finds the new client and shows **Delete test enquiry**. That button only deletes a client whose first
name is `Test` and whose email matches the test. If the company is read-only, the screen says the link works but
nothing was saved.

On the Google tab, Google's own **Send test data** checks the link, but its lead isn't saved (`is_test`). The screen
says so.

## Guides (in the screen)

Each step below was checked against the provider's own docs or plugin page on 31 Oct 2026:

- **Website:**
  - Paste-in HTML form. It posts `FormData` to the link and has a hidden `website_url` spam-trap field.
  - Contact Form 7 with the free "CF7 to Webhook" plugin (wordpress.org `cf7-to-zapier`). Fields are renamed with
    `webhook:`.
  - Elementor Pro: Actions After Submit › Webhook. It sends form data keyed by the field labels.
  - WPForms: the Webhooks addon needs an Elite licence.
  - Gravity Forms: the Webhooks Add-On needs an Elite or Nonprofit licence.
  - Zapier.
  - The table of accepted field names mirrors `FIELD_ALIASES`.
- **Meta Lead Ads:**
  - Zapier: Facebook Lead Ads "New Lead" › Webhooks by Zapier "POST", Payload Type json, with a mapping table.
    Webhooks by Zapier is a Premium app, so it needs a paid plan or the trial.
  - Make: Facebook Lead Ads "New Lead" (instant) › HTTP "Make a request", POST, form-urlencoded. Make has a free plan
    with a monthly credit limit.
  - The Meta Lead Ads Testing Tool.
- **Google Ads:** Campaigns › Assets › Lead form › edit › Export leads from Google Ads › Other data integration
  options › Webhook integration. Paste the URL and the key, then click Send test data and Save. The function already
  reads `google_key` and `user_column_data`.

If you change `FIELD_ALIASES` in `website-enquiry`, update `LEAD_FIELDS` in `index.html` too.

## Going live

1. Done 31 Oct 2026, 12:58 PM AEDT: applied `supabase/migrations/20261031150000_lead_connections.sql` to production
   (`qjkmkmmrgtoaocygymqo`). There were no `lead_sources` rows at the time, so no duplicates.
2. No edge function deploy is needed (v17 already matches the repo).
3. Merge the PR. Sign in as an owner, create a Website key, send a test enquiry, then delete it.
4. Existing `lead_sources` rows show up in the screen straight away. Any company with more than one key for the same
   channel shows the oldest, so check with
   `select company_id, channel, count(*) from lead_sources group by 1,2 having count(*)>1;`.

Rollback: run `supabase/rollback/20261031150000_lead_connections_undo.sql`. The screen goes back to "aren't switched on yet", and existing keys keep working.
