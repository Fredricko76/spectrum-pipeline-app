-- Undo 20261030120000_db_security_hardening: restores the grants, policies and
-- invitation_preview body exactly as they were on production (qjkmkmmrgtoaocygymqo) on 2026-10-30.
begin;

grant execute on function public.trg_shadow_from_membership() to public, anon, authenticated;
grant execute on function public.trg_shadow_from_profile()    to public, anon, authenticated;
grant execute on function public.guard_current_company()      to authenticated;
grant execute on function public.guard_invitation_role()      to authenticated;
grant execute on function public.record_stage_event()         to authenticated;
grant execute on function public.touch_updated_at()           to authenticated;

grant execute on function public.auth_role()                                 to authenticated;
grant execute on function public.company_has_other_owner(uuid, uuid)        to authenticated;
grant execute on function public.readmit_user(text, text, public.user_role) to authenticated;
grant execute on function public.refresh_profile_shadow(uuid)               to authenticated;
grant execute on function public.remove_member(uuid)                        to authenticated;
grant execute on function public.seats_used(uuid)                           to authenticated;

grant execute on function public.dashboard_month_names(text, uuid) to public, anon;

create or replace function public.invitation_preview(p_token uuid)
returns table(company_name text, role public.user_role, email text, valid boolean, reason text, seats_available boolean)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select c.name, i.role, i.email,
    (i.status='pending' and i.expires_at > now()
      and public.seats_used(i.company_id) < c.seat_limit),
    case
      when i.status='accepted' then 'This invite has already been used.'
      when i.status='revoked'  then 'This invite was cancelled.'
      when i.expires_at <= now() then 'This invite has expired.'
      when public.seats_used(i.company_id) >= c.seat_limit
        then 'All seats for this company are in use. Ask the owner to add a seat, then try again.'
      else null
    end,
    (public.seats_used(i.company_id) < c.seat_limit)
  from public.invitations i join public.companies c on c.id = i.company_id
  where i.token = p_token;
$function$;

drop policy if exists server_only_deny_all on public.lead_sources;
drop policy if exists server_only_deny_all on public.platform_admins;
drop policy if exists server_only_deny_all on public.platform_audit;
drop policy if exists server_only_deny_all on public.platform_messages;
drop policy if exists server_only_deny_all on public.stripe_events;

grant all on table public.platform_admins to anon, authenticated;
grant all on table public.platform_audit  to anon, authenticated;

comment on table public.platform_admins   is null;
comment on table public.platform_audit    is null;
comment on table public.platform_messages is null;
comment on table public.stripe_events     is null;

commit;
