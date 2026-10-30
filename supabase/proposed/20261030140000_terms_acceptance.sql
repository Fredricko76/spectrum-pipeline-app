-- Terms of Service / Privacy Policy acceptance record.
-- NOT APPLIED. This is optional and separate from the legal-pages change, which works without it.
--
-- The sign-up form already sends terms_version + terms_accepted_at (client clock) in the auth user
-- metadata, so auth.users.raw_user_meta_data holds a record even without this migration.
-- This migration adds a tamper-resistant, append-only copy stamped with the SERVER clock:
--   * public.terms_acceptances: one row per acceptance (user, version, server time, client time).
--     RLS on. Users can read only their own rows. No insert/update/delete for anon or authenticated:
--     rows are written only by handle_new_user(), which is SECURITY DEFINER.
--   * handle_new_user(): identical to the live definition (read 2026-10-30), plus one insert
--     when the sign-up metadata includes terms_version.
-- Users who signed up before this change have no row.
-- Undo: supabase/proposed/20261030140000_terms_acceptance_undo.sql
-- Kept in supabase/proposed/ (not migrations/) so nothing applies it by accident. To adopt it, move it into
-- supabase/migrations/ and apply it deliberately.

create table if not exists public.terms_acceptances (
  id                bigint generated always as identity primary key,
  user_id           uuid not null references auth.users(id) on delete cascade,
  terms_version     text not null,
  accepted_at       timestamptz not null default now(),
  client_accepted_at timestamptz,
  constraint terms_acceptances_version_len check (char_length(terms_version) <= 40)
);
create index if not exists terms_acceptances_user_idx on public.terms_acceptances(user_id);

alter table public.terms_acceptances enable row level security;
revoke all on public.terms_acceptances from anon, authenticated;
grant select on public.terms_acceptances to authenticated;

drop policy if exists terms_acceptances_select_own on public.terms_acceptances;
create policy terms_acceptances_select_own on public.terms_acceptances
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_platform_admin());

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_token uuid; v_invite public.invitations%rowtype;
  v_company_id uuid; v_role public.user_role; v_company_nm text;
  v_terms text; v_client_ts timestamptz;
begin
  begin
    v_token := nullif(new.raw_user_meta_data->>'invite_token','')::uuid;
  exception when others then v_token := null;
  end;

  if v_token is not null then
    select * into v_invite from public.invitations
     where token = v_token and status = 'pending' and expires_at > now()
     limit 1;
    if not found then
      raise exception 'That invitation is invalid, already used, or expired.' using errcode = 'P0001';
    end if;

    if public.seats_used(v_invite.company_id)
       >= (select seat_limit from public.companies where id = v_invite.company_id) then
      raise exception 'This company has used all of its seats. Ask the owner to add another.'
        using errcode = 'P0001';
    end if;

    v_company_id := v_invite.company_id;
    v_role       := v_invite.role;
    update public.invitations set status='accepted', accepted_at=now() where id = v_invite.id;
  else
    v_company_nm := coalesce(nullif(trim(new.raw_user_meta_data->>'company_name'),''), 'My Company');
    -- billing: a self-serve company has no subscription until it starts a trial in Checkout
    insert into public.companies (name, subscription_status, is_comped)
    values (v_company_nm, 'none', false) returning id into v_company_id;
    v_role := 'owner';
  end if;

  insert into public.profiles (id, full_name, email, current_company_id)
  values (new.id,
          nullif(trim(new.raw_user_meta_data->>'full_name'),''),
          new.email,
          v_company_id);

  insert into public.company_members (user_id, company_id, role)
  values (new.id, v_company_id, v_role);

  -- legal: record Terms / Privacy acceptance from the sign-up tick box (server time is authoritative)
  v_terms := left(nullif(trim(new.raw_user_meta_data->>'terms_version'),''), 40);
  if v_terms is not null then
    begin
      v_client_ts := (new.raw_user_meta_data->>'terms_accepted_at')::timestamptz;
    exception when others then v_client_ts := null;
    end;
    insert into public.terms_acceptances (user_id, terms_version, client_accepted_at)
    values (new.id, v_terms, v_client_ts);
  end if;

  return new;
end;
$function$;
