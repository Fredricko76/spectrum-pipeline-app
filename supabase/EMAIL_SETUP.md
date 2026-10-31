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

## 7. Scanner-safe reset links (token_hash + Continue screen)

**Why:** Supabase's default email link (`{{ .ConfirmationURL }}`) uses up the one-time token as soon as anything opens it. Microsoft 365 Safe Links and similar mail scanners open links before the person does, so the person then sees "expired or already used". In the 31 Oct 2026 test, Microsoft's scanner used Fred's reset link 22 seconds after it was sent.

**Fix:** the email links straight to the app with `token_hash`. The app shows "Reset your password" with a **Continue** button and only calls `supabase.auth.verifyOtp({ token_hash, type: "recovery" })` when the person taps it. A scanner that only opens the page uses nothing.

### Current live template (before the change)
I couldn't read it (no Supabase management API access), so it is presumed to be the Supabase default. Fred, check it under Authentication -> Emails -> Templates -> Reset password:
- Subject: `Reset Your Password`
- Body:
```html
<h2>Reset Password</h2>
<p>Follow this link to reset the password for your user:</p>
<p><a href="{{ .ConfirmationURL }}">Reset Password</a></p>
```
Keep a copy of what is actually there. Pasting it back is the rollback.

### New "Reset password" template
- Subject: `Reset your Spectrum Sales Pipeline password`
- Body: the full contents of `supabase/email-templates/reset-password.html`
- The link is `{{ .SiteURL }}/?recovery=1&token_hash={{ .TokenHash }}&type=recovery`. Site URL is `https://spectrumsalesonline.net` with no trailing slash, so it resolves to `https://spectrumsalesonline.net/?recovery=1&token_hash=...&type=recovery`.

### Go-live order (so no reset email breaks in between)
1. **Merge the app change first** and wait for the Netlify production deploy to finish. The app then handles both link styles: the old `#access_token` links already in inboxes and the new `token_hash` links.
2. **Then** paste the new subject and body into Authentication -> Emails -> Templates -> Reset password on production and save.
   Never do this step before step 1. The old app ignores `token_hash`, so new links would just land on the sign-in screen.
3. Test: use "Forgotten your password?" with an address you own. The email's button should open "Reset your password" with Continue. Tap it, then close the "Choose a new password" window without saving if you don't want to change your password.
4. Rollback (if ever needed): paste the old template back. The app still handles old links, so no app change is needed.

Note: `{{ .SiteURL }}` always points to spectrumsalesonline.net, including for resets requested from spectrum-pipeline-app.netlify.app. That's fine because both use the same database. Deploy previews use billing-test, which has its own templates and Site URL.

### Sign-up confirmation (optional)
The app handles `?confirm=1&token_hash=...&type=email` (or `type=signup`) the same way: "Confirm your email" -> Continue -> `verifyOtp` -> signed in.
Production looks like it has **Confirm email turned off**: 11 of 12 users were confirmed without a confirmation email being sent (the last one went out on 16 Aug 2026). If Fred turns Confirm email on, paste `supabase/email-templates/confirm-signup.html` into the "Confirm signup" template (subject: `Confirm your email for Spectrum Sales Pipeline`), after the merge, the same way.
