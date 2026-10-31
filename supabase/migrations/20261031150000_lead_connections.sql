-- PROPOSED - not applied. Lead connections screen (company owners/admins manage their own lead keys).
--
-- public.lead_sources stays server-only: its restrictive deny-all policy for anon/authenticated is
-- unchanged, and there are still no table grants to those roles. Owners/admins reach their own
-- company's rows only through the SECURITY DEFINER functions below, which all scope to
-- auth_company_id() and require is_manager(). Consultants and other companies get nothing.
--
-- One key per channel (Website / Meta / Google) so each lead is tagged with the right lead source.
-- Additive only: four new functions, no table, column, policy or data changes.
-- Undo: 20261031150000_lead_connections_undo.sql

-- Keys look like lk_ + 48 hex characters (192 random bits from two v4 UUIDs).
create or replace function public.lead_source_new_key()
returns text
language sql
volatile
set search_path = ''
as $$
  select 'lk_' || replace(gen_random_uuid()::text, '-', '')
               || substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
$$;
revoke all on function public.lead_source_new_key() from public, anon, authenticated;

-- List this company's lead connections (owners/admins only; empty for anyone else).
create or replace function public.my_lead_sources()
returns table(id uuid, channel text, label text, site_key text, active boolean,
              default_owner_id uuid, default_owner_name text, timezone text, created_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.channel, s.label, s.site_key, s.active,
         s.default_owner_id, coalesce(p.full_name, p.email), s.timezone, s.created_at
    from public.lead_sources s
    left join public.profiles p on p.id = s.default_owner_id
   where public.is_manager()
     and public.auth_company_id() is not null
     and s.company_id = public.auth_company_id()
   order by array_position(array['Website','Meta','Google','Other'], s.channel), s.created_at;
$$;

-- Create the company's key for a channel. If one already exists it is returned unchanged
-- (switched back on if it had been turned off), so a double click never makes two keys.
create or replace function public.lead_source_create(p_channel text, p_timezone text default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := public.auth_company_id();
  v_id uuid;
  v_tz text := 'Australia/Sydney';
begin
  if v_company is null or not public.is_manager() then
    raise exception 'Only company owners and admins can manage lead connections.' using errcode = '42501';
  end if;
  if p_channel is null or p_channel not in ('Website', 'Meta', 'Google') then
    raise exception 'Unknown lead channel.' using errcode = '22023';
  end if;
  if not public.company_can_write(v_company) then
    raise exception 'Your company is read-only. Choose a plan to connect lead forms.' using errcode = '42501';
  end if;
  if p_timezone is not null and exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    v_tz := p_timezone;
  end if;

  -- one creator at a time per company, so two clicks can't make two keys
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('lead_sources:' || v_company::text));

  select s.id into v_id
    from public.lead_sources s
   where s.company_id = v_company and s.channel = p_channel
   order by s.active desc, s.created_at
   limit 1;
  if v_id is not null then
    update public.lead_sources set active = true where id = v_id and not active;
    return v_id;
  end if;

  insert into public.lead_sources (label, site_key, company_id, default_owner_id, timezone, channel)
  values (case p_channel when 'Website' then 'Website form'
                         when 'Meta'    then 'Meta Lead Ads'
                         else 'Google Ads lead form' end,
          public.lead_source_new_key(), v_company, auth.uid(), v_tz, p_channel)
  returning id into v_id;
  return v_id;
end;
$$;

-- Replace a key. The old key stops working immediately.
create or replace function public.lead_source_regenerate(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := public.auth_company_id();
  v_id uuid;
begin
  if v_company is null or not public.is_manager() then
    raise exception 'Only company owners and admins can manage lead connections.' using errcode = '42501';
  end if;
  update public.lead_sources
     set site_key = public.lead_source_new_key()
   where id = p_id and company_id = v_company
  returning id into v_id;
  if v_id is null then
    raise exception 'Lead connection not found.' using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;

-- Change who new leads are assigned to, and/or switch a connection off or on.
-- p_default_owner must be an active member of the company. Pass null to leave a value unchanged.
create or replace function public.lead_source_update(p_id uuid, p_default_owner uuid default null, p_active boolean default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_company uuid := public.auth_company_id();
  v_id uuid;
begin
  if v_company is null or not public.is_manager() then
    raise exception 'Only company owners and admins can manage lead connections.' using errcode = '42501';
  end if;
  if p_default_owner is not null and not exists (
       select 1 from public.company_members m
        where m.user_id = p_default_owner and m.company_id = v_company and m.active) then
    raise exception 'That person is not an active member of your company.' using errcode = '22023';
  end if;
  update public.lead_sources
     set default_owner_id = coalesce(p_default_owner, default_owner_id),
         active           = coalesce(p_active, active)
   where id = p_id and company_id = v_company
  returning id into v_id;
  if v_id is null then
    raise exception 'Lead connection not found.' using errcode = 'P0002';
  end if;
  return v_id;
end;
$$;

revoke all on function public.my_lead_sources()                          from public, anon;
revoke all on function public.lead_source_create(text, text)             from public, anon;
revoke all on function public.lead_source_regenerate(uuid)               from public, anon;
revoke all on function public.lead_source_update(uuid, uuid, boolean)    from public, anon;
grant execute on function public.my_lead_sources()                       to authenticated;
grant execute on function public.lead_source_create(text, text)          to authenticated;
grant execute on function public.lead_source_regenerate(uuid)            to authenticated;
grant execute on function public.lead_source_update(uuid, uuid, boolean) to authenticated;

comment on function public.my_lead_sources() is
  'Lead connections (website/Meta/Google keys) for the caller''s current company. Owners/admins only.';
