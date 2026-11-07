# Australian address suggestions

The client form can suggest Australian addresses while someone types a property / build address (the primary address and each additional dwelling). Picking a suggestion fills street number, street name and suburb. Estate is filled only when Google returns a neighbourhood name; otherwise the estate box is left as the user typed it. An address that is not in the list can still be typed and saved.

Nothing here is live until the steps below are done. This change does not deploy the function, does not set a secret, and does not touch the production Supabase project or the production Netlify site.

## What was added

- `supabase/functions/address-suggest` — a signed-in edge function. It calls Places API (New): Autocomplete, then Place Details for the one place the user picks.
- The browser sends a UUID v4 session token on both calls, and a new token after a choice or after leaving the address. Google bills that pair as one session.
- Results are restricted to Australia (`includedRegionCodes: ["au"]`) and biased to a fixed box around the continent. The browser does not request device location, and the function does not forward the caller's IP or GPS.
- If `GOOGLE_PLACES_API_KEY` is not set, the function answers `{ "configured": false }` and the form stays the four plain text boxes it is today. No error is shown.

Saved clients are not rewritten. There is no database migration. Postcode and state are not stored; the dwellings table still has `street_no`, `street_name`, `suburb` and `estate` only.

## Secret

| Name | Where | Notes |
|---|---|---|
| `GOOGLE_PLACES_API_KEY` | Supabase function secret only | Google Cloud API key. Never put it in `index.html`, Netlify env, or git. |

The key must stay server-side. The page already ships a Supabase publishable key; that key is not a Google key and must not be replaced with one.

## Google Cloud

1. In the Google Cloud project that should pay for this, enable **Places API (New)** (`places.googleapis.com`). The legacy Places API is not what this function calls.
2. Create an API key. Restrict it to **Places API (New)** only.
3. Do not add an HTTP-referrer restriction. The key is used from the edge function, not from the browser, so a referrer restriction would make every lookup fail. Application restrictions that only allow browser referrers will not work.
4. Do not commit the key.

Suggested key name: `spectrum-pipeline-places`.

## Turning it on (test project only, when you are ready)

Production project ref `qjkmkmmrgtoaocygymqo` is out of scope for this change. Do not set the secret there and do not deploy this function there until you have decided to go live.

The Netlify deploy preview rewrites the site at the Supabase **billing-test** branch (`wwdhiailerkmwpnuqpvm`), not production. Suggestions on a preview work only after the function and the secret exist on that branch:

```bash
supabase secrets set GOOGLE_PLACES_API_KEY=YOUR_KEY --project-ref wwdhiailerkmwpnuqpvm
supabase functions deploy address-suggest --project-ref wwdhiailerkmwpnuqpvm
```

`verify_jwt` is true in `supabase/config.toml`. Leave it true. The function trusts the gateway's JWT check and does not re-verify the signature itself.

Confirm on a deploy preview (not the production site):

1. Add or edit a client, type a few letters of a street in Street name (or Street no. / Suburb).
2. A list of Australian addresses appears, with a Google Maps attribution under it.
3. Choosing one fills street number, street name and suburb. Estate changes only when the result includes a neighbourhood.
4. Arrow keys move, Enter chooses, Escape closes the list. Saving still works if you ignore the list and type your own address.
5. Add a dwelling and repeat.
6. With the secret removed, the same fields type and save with no list and no error.

## Privacy

While suggestions are switched on, the street text being typed is sent to our function and then to Google. `privacy.html` and `dpa.html` list Google Maps Platform (Places API) for that. The DPA promises account owners notice before a new subprocessor is added. Do not set the production secret until that notice has been given.

Device location is not requested. The address saved on the client is still only the four existing fields.

## Rollback

The form works with or without the function.

- Stop suggestions: delete the `GOOGLE_PLACES_API_KEY` secret, or undeploy `address-suggest`. The page then gets `configured: false` (or a failed call) and keeps the plain fields. No client rows change.
- Remove the feature from the app: revert this change. There is no migration to undo.

## Local check

```bash
deno test -A supabase/functions/address-suggest/address_suggest_test.ts
```

The test does not call Google and does not need a key.
