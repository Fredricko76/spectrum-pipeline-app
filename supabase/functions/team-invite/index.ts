// POST /functions/v1/team-invite   { invitation_id }  ->  { sent, link, email, reason? }
//
// Emails a pending team invitation to the person being invited. The invite itself is still
// created by the app (insert into public.invitations, guarded by RLS + guard_invitation_role);
// this function only delivers the existing "?invite=<token>" link, so "Copy link" keeps working
// and nothing about how an invite is accepted changes (handle_new_user still does that at sign-up).
//
// Only an owner or admin of the company the caller is currently acting as may send (callerCompany
// -> my_billing().can_manage, the same check the billing functions use).
//
// Env (Supabase function secrets, never in the repo):
//   RESEND_API_KEY   re_... Resend API key with sending access. If it is not set the function does
//                    NOT fail: it answers { sent:false, reason:"email_not_configured", link } and the
//                    app shows the link to copy instead.
//   INVITE_FROM      optional, default "Spectrum Sales Pipeline <noreply@spectrumsalesonline.net>"
//                    (the domain must be verified in Resend).
//   APP_URL / ALLOWED_ORIGINS / SENTRY_DSN   as for the billing functions (_shared/billing.ts).
import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { adminClient, appUrl, callerCompany, corsHeaders, HttpError, json } from "../_shared/billing.ts";
import { reportError } from "../_shared/sentry.ts";

const RESEND_ENDPOINT = "https://api.resend.com/emails";
const DEFAULT_FROM = "Spectrum Sales Pipeline <noreply@spectrumsalesonline.net>";
const RESEND_COOLDOWN_SECONDS = 60; // per invitation, only enforced once the proposed migration adds last_emailed_at
const MAX_SENDS_PER_INVITE = 10;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

/** The link goes to the origin the manager is using if it is one we trust (CORS allow-list), else APP_URL. */
function linkBase(req: Request): string {
  const origin = req.headers.get("origin") ?? "";
  return origin && corsHeaders(req)["Access-Control-Allow-Origin"] === origin ? origin : appUrl();
}

const ROLE_LABEL: Record<string, string> = { consultant: "a consultant", admin: "an admin", owner: "an owner" };

function inviteEmail(p: { company: string; inviter: string; role: string; link: string; expires: string }) {
  const role = ROLE_LABEL[p.role] ?? p.role;
  const subject = `${p.inviter} invited you to join ${p.company} on Spectrum Sales Pipeline`;
  const text = [
    `Hi,`,
    ``,
    `${p.inviter} has invited you to join ${p.company} on Spectrum Sales Pipeline as ${role}.`,
    ``,
    `Accept the invite and create your login here:`,
    p.link,
    ``,
    `Use this email address when you create your account. The link expires on ${p.expires}.`,
    ``,
    `If you were not expecting this, you can ignore this email.`,
  ].join("\n");
  const h = escapeHtml;
  const html = `<!doctype html><html><body style="margin:0;background:#f4f6fa;font-family:Arial,Helvetica,sans-serif;color:#1f2937">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6fa;padding:24px 0"><tr><td align="center">
<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#ffffff;border-radius:10px;overflow:hidden">
<tr><td style="background:#1E3A8A;color:#ffffff;padding:18px 24px;font-size:18px;font-weight:bold">Spectrum Sales Pipeline</td></tr>
<tr><td style="padding:24px;font-size:15px;line-height:1.55">
<p style="margin:0 0 14px">Hi,</p>
<p style="margin:0 0 14px"><strong>${h(p.inviter)}</strong> has invited you to join <strong>${h(p.company)}</strong> on Spectrum Sales Pipeline as ${h(role)}.</p>
<p style="margin:22px 0"><a href="${h(p.link)}" style="background:#1E3A8A;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:bold;display:inline-block">Accept invite</a></p>
<p style="margin:0 0 14px;font-size:13px;color:#4b5563">Use this email address when you create your account. The link expires on ${h(p.expires)}.</p>
<p style="margin:0 0 14px;font-size:13px;color:#4b5563">If the button does not work, copy this link into your browser:<br><a href="${h(p.link)}" style="color:#1E3A8A;word-break:break-all">${h(p.link)}</a></p>
<p style="margin:18px 0 0;font-size:12px;color:#6b7280">If you were not expecting this, you can ignore this email.</p>
</td></tr></table></td></tr></table></body></html>`;
  return { subject, text, html };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, 405, { error: "Method not allowed" });
  try {
    const me = await callerCompany(req);
    if (!me.canManage) throw new HttpError(403, "Only an owner or admin can send invites.");

    let body: { invitation_id?: string } = {};
    try { body = await req.json(); } catch { /* empty body */ }
    const id = String(body.invitation_id ?? "");
    if (!UUID.test(id)) throw new HttpError(400, "Missing invitation_id.");

    const admin = adminClient();
    // select("*") so the function works before and after the optional proposed migration
    const { data: inv, error: iErr } = await admin.from("invitations").select("*").eq("id", id).maybeSingle();
    if (iErr) throw iErr;
    // same answer for "not found" and "another company's invite", so ids cannot be probed
    if (!inv || inv.company_id !== me.companyId) throw new HttpError(404, "Invite not found.");
    if (inv.status !== "pending") throw new HttpError(409, "This invite has already been used or was cancelled.");
    if (new Date(inv.expires_at).getTime() <= Date.now()) {
      throw new HttpError(409, "This invite has expired. Choose Resend to renew it.");
    }

    const link = `${linkBase(req)}/?invite=${inv.token}`;
    const tracked = "last_emailed_at" in inv;
    if (tracked && inv.last_emailed_at &&
        Date.now() - new Date(inv.last_emailed_at).getTime() < RESEND_COOLDOWN_SECONDS * 1000) {
      throw new HttpError(429, "That invite was emailed less than a minute ago. Give it a moment to arrive.");
    }
    if (tracked && (inv.email_count ?? 0) >= MAX_SENDS_PER_INVITE) {
      throw new HttpError(429, "This invite has been emailed too many times. Copy the link and send it yourself.");
    }

    const apiKey = (Deno.env.get("RESEND_API_KEY") ?? "").trim();
    if (!apiKey) {
      console.warn("team-invite: RESEND_API_KEY is not set; returning the link only");
      return json(req, 200, { sent: false, reason: "email_not_configured", link, email: inv.email });
    }

    const { data: prof } = await admin.from("profiles").select("full_name").eq("id", me.userId).maybeSingle();
    const inviter = (prof?.full_name || me.email || "Your team").trim();
    const expires = new Date(inv.expires_at).toLocaleDateString("en-AU", {
      day: "numeric", month: "long", year: "numeric", timeZone: "Australia/Melbourne",
    });
    const msg = inviteEmail({ company: me.companyName, inviter, role: inv.role, link, expires });

    const res = await fetch(RESEND_ENDPOINT, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: (Deno.env.get("INVITE_FROM") ?? "").trim() || DEFAULT_FROM,
        to: [inv.email],
        reply_to: me.email ? [me.email] : undefined,
        subject: msg.subject,
        text: msg.text,
        html: msg.html,
        tags: [{ name: "type", value: "team_invite" }],
      }),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => "");
      console.error("team-invite: Resend error", res.status, detail.slice(0, 300));
      await reportError("team-invite", new Error(`Resend ${res.status}`));
      return json(req, 502, { sent: false, reason: "send_failed", link, email: inv.email,
        error: "The invite email could not be sent. Copy the link and send it yourself." });
    }

    if (tracked) {
      await admin.from("invitations")
        .update({ last_emailed_at: new Date().toISOString(), email_count: (inv.email_count ?? 0) + 1 })
        .eq("id", inv.id);
    }
    return json(req, 200, { sent: true, link, email: inv.email });
  } catch (e) {
    if (e instanceof HttpError) return json(req, e.status, { error: e.message });
    console.error("team-invite error", e instanceof Error ? e.message : e);
    await reportError("team-invite", e);
    return json(req, 500, { error: "Invites could not be emailed right now. Copy the link instead." });
  }
});
