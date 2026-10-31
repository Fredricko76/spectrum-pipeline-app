# Emailed team invites and password reset: go-live checklist

Nothing here is live until these steps are done. Fred runs them himself.

## Why this is needed
- Supabase's built-in email service only delivers to members of the Supabase project team and has a very low hourly limit. Customers never receive reset emails from it.
- Team invites were link-only. The new `team-invite` edge function emails the invite link through Resend.

## 1. Resend
1. In Resend, add and verify the sending domain (`spectrumsalesonline.net`, or reuse `spectrumcoachmasteringsales.com`). Add the DNS records Resend shows (SPF/DKIM, optional DMARC) at the domain registrar.
2. Create an API key with "Sending access" only (one key for Supabase Auth SMTP, one for the edge function, so either can be rotated separately).

## 2. Supabase Auth (production dashboard)
1. Authentication -> Emails -> SMTP settings -> enable custom SMTP:
   host `smtp.resend.com`, port `465`, username `resend`, password = the Resend API key,
   sender email e.g. `noreply@spectrumsalesonline.net`, sender name `Spectrum Sales Pipeline`.
2. Authentication -> Rate limits -> raise "emails sent per hour" (starts at 30 after custom SMTP).
3. Authentication -> URL Configuration:
   - Site URL: `https://spectrumsalesonline.net`
   - Redirect URLs:
     - `https://spectrumsalesonline.net/**`
     - `https://spectrum-pipeline-app.netlify.app/**`
     - `https://*--spectrum-pipeline-app.netlify.app/**` (deploy previews; only needed on billing-test if previews point there)
4. Optional: review the "Reset password" email template. The default `{{ .ConfirmationURL }}` link works with the app.
5. Decide on "Secure password change" (Authentication -> Providers -> Email). If on, changing a password in-app may ask for a recent sign-in; the app then points people to "Email me a reset link".

## 3. Edge function
```
supabase secrets set RESEND_API_KEY=... --project-ref qjkmkmmrgtoaocygymqo
# optional
supabase secrets set INVITE_FROM="Spectrum Sales Pipeline <noreply@spectrumsalesonline.net>" --project-ref qjkmkmmrgtoaocygymqo
supabase functions deploy team-invite --project-ref qjkmkmmrgtoaocygymqo   # verify_jwt = true via config.toml
```
Without `RESEND_API_KEY` the function answers `email_not_configured` and the app shows the Copy link fallback.

## 4. Optional migration
`supabase/proposed/20261031120000_invitation_email_tracking.sql` adds `last_emailed_at` and `email_count` so the function can enforce a 60-second resend cooldown and a 10-email cap per invite. Undo: `..._undo.sql`. Both the app and the function work without it.

## 5. Privacy and DPA
Resend is a new subprocessor. `privacy.html` and `dpa.html` list it in this PR. DPA clause 7.2 promises account owners 30 days' notice before a new subprocessor is added.

## 6. Test, then merge
Test on the deploy preview (billing-test) or on production with an address you own, then merge.
