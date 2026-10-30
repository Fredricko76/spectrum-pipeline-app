-- Database security hardening (Supabase advisor warnings, 2026-10-30).
-- Undo: supabase/rollback/20261030120000_db_security_hardening_undo.sql
--
-- What stays callable by signed-in users, and why:
--   * every function the app calls with sb.rpc() (index.html, incl. the platform panel's call() helper);
--   * helpers used inside RLS policies or SECURITY INVOKER functions, which run as the caller:
--     auth_company_id, can_reach_client, can_view_sales_reports, can_manage_sales_reports,
--     company_can_write, is_manager, shares_current_company.
--   Each remaining SECURITY DEFINER function checks the caller itself (auth.uid(), is_manager(),
--   require_platform_admin()), so the advisor's remaining "signed-in users can execute" warnings
--   for them are expected.
-- Edge functions use service_role (or the caller's JWT for my_billing / company_access), and
-- service_role keeps every grant below.

begin;

-- 1. Trigger functions: Postgres does not check EXECUTE when a trigger fires, so nobody needs it.
revoke execute on function public.trg_shadow_from_membership() from public, anon, authenticated;
revoke execute on function public.trg_shadow_from_profile()    from public, anon, authenticated;
revoke execute on function public.guard_current_company()      from public, anon, authenticated;
revoke execute on function public.guard_invitation_role()      from public, anon, authenticated;
revoke execute on function public.record_stage_event()         from public, anon, authenticated;
revoke execute on function public.touch_updated_at()           from public, anon, authenticated;

-- 2. SECURITY DEFINER functions the app never calls directly (only from other definer functions,
--    which run as their owner). readmit_user was an old SQL-editor helper.
revoke execute on function public.auth_role()                                   from public, anon, authenticated;
revoke execute on function public.company_has_other_owner(uuid, uuid)          from public, anon, authenticated;
revoke execute on function public.readmit_user(text, text, public.user_role)   from public, anon, authenticated;
revoke execute on function public.refresh_profile_shadow(uuid)                 from public, anon, authenticated;
revoke execute on function public.remove_member(uuid)                          from public, anon, authenticated;
revoke execute on function public.seats_used(uuid)                             from public, anon, authenticated;

-- 3. Dashboard helper was also open to anonymous callers; the dashboard is signed-in only.
revoke execute on function public.dashboard_month_names(text, uuid) from public, anon;

-- 4. invitation_preview must stay callable before sign-in (invite link -> sign-up form).
--    Hardened: empty search_path, and company name / role / email are only returned for a
--    usable invite; invalid, used, expired or full invites return just valid=false + a reason.
create or replace function public.invitation_preview(p_token uuid)
returns table(company_name text, role public.user_role, email text, valid boolean, reason text, seats_available boolean)
language sql
stable
security definer
set search_path = ''
as $$
  with inv as (
    select i.status, i.expires_at, i.role, i.email, c.name, c.seat_limit,
           public.seats_used(i.company_id) as used
      from public.invitations i
      join public.companies c on c.id = i.company_id
     where p_token is not null and i.token = p_token
  ), v as (
    select inv.*, (inv.status = 'pending' and inv.expires_at > now() and inv.used < inv.seat_limit) as ok
      from inv
  )
  select case when v.ok then v.name end,
         case when v.ok then v.role end,
         case when v.ok then v.email end,
         v.ok,
         case
           when v.status = 'accepted' then 'This invite has already been used.'
           when v.status = 'revoked'  then 'This invite was cancelled.'
           when v.expires_at <= now() then 'This invite has expired.'
           when v.used >= v.seat_limit
             then 'All seats for this company are in use. Ask the owner to add a seat, then try again.'
           else null
         end,
         case when v.ok then true end
    from v;
$$;
revoke execute on function public.invitation_preview(uuid) from public;
grant  execute on function public.invitation_preview(uuid) to anon, authenticated, service_role;

-- 5. Server-only tables (RLS on, no policies = no access for anon/authenticated).
--    Make that explicit: drop the leftover table grants and add a restrictive deny-all policy.
--    service_role and the table owner (used by SECURITY DEFINER functions) bypass RLS.
revoke all on table public.platform_admins from anon, authenticated;
revoke all on table public.platform_audit  from anon, authenticated;

create policy server_only_deny_all on public.lead_sources      as restrictive for all to anon, authenticated using (false) with check (false);
create policy server_only_deny_all on public.platform_admins   as restrictive for all to anon, authenticated using (false) with check (false);
create policy server_only_deny_all on public.platform_audit    as restrictive for all to anon, authenticated using (false) with check (false);
create policy server_only_deny_all on public.platform_messages as restrictive for all to anon, authenticated using (false) with check (false);
create policy server_only_deny_all on public.stripe_events     as restrictive for all to anon, authenticated using (false) with check (false);

comment on table public.lead_sources      is 'Server-only: read by the website-enquiry edge function (service_role).';
comment on table public.platform_admins   is 'Server-only: read via is_platform_admin()/require_platform_admin() (SECURITY DEFINER).';
comment on table public.platform_audit    is 'Server-only: written by platform_log() (SECURITY DEFINER).';
comment on table public.platform_messages is 'Server-only: chat is disabled; only SECURITY DEFINER functions touch it.';
comment on table public.stripe_events     is 'Server-only: stripe-webhook idempotency log (service_role).';

commit;
