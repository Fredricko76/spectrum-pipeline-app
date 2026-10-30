-- =============================================================================
-- Stripe billing, step 1 (database).            Undo: rollback/20261030100000_stripe_billing_undo.sql
--
-- * companies gets Stripe + subscription columns and an is_comped flag.
-- * The 5 existing companies are comped: they keep full access, their plan and
--   seat values, and are never touched by the Stripe webhook.
-- * company_access(): 'comped' | 'full' | 'grace' | 'read_only'
--     comped                      -> full access, no billing UI
--     trialing / active           -> full
--     past_due  (< 7 days)        -> grace (full access + "update card" banner)
--     past_due >= 7 days, unpaid, canceled, incomplete*, paused, none -> read_only
--   Reads are NEVER blocked. Writes (insert/update/delete) on content tables are
--   blocked by RESTRICTIVE policies when access is read_only.
-- * plan / seat_limit / Stripe columns can no longer be changed by owners or admins:
--   table-level UPDATE on companies is replaced by column grants for profile fields,
--   and set_seat_limit() only works for comped companies or the platform admin.
--   Paid companies get plan + seat_limit from the Stripe price via the webhook
--   (service role).
-- * New non-invite sign-ups start with subscription_status 'none' (read-only until
--   they start a trial through Stripe Checkout).
-- * Companies created by the platform admin (provision_company) also start with status
--   'none' and is_comped = false. Making a company free is a deliberate choice:
--   platform_set_company_comped() (platform admins only; the 'Complimentary (free)'
--   toggle in the platform panel).
-- =============================================================================

begin;

-- 1. Columns ------------------------------------------------------------------
alter table public.companies
  add column stripe_customer_id     text,
  add column stripe_subscription_id text,
  add column stripe_price_id        text,
  add column subscription_status    text not null default 'none',
  add column trial_ends_at          timestamptz,
  add column current_period_end     timestamptz,
  add column cancel_at_period_end   boolean not null default false,
  add column past_due_since         timestamptz,
  add column billing_updated_at     timestamptz,
  add column is_comped              boolean not null default false,
  add column comped_reason          text;

-- Stripe plans are starter / team / network; keep the legacy values for existing rows.
alter table public.companies drop constraint companies_plan_check;
alter table public.companies add constraint companies_plan_check
  check (plan in ('solo','starter','team','network','enterprise'));

alter table public.companies
  add constraint companies_stripe_customer_id_key     unique (stripe_customer_id),
  add constraint companies_stripe_subscription_id_key unique (stripe_subscription_id),
  add constraint companies_subscription_status_check  check (subscription_status in
    ('none','trialing','active','past_due','unpaid','canceled','incomplete','incomplete_expired','paused'));

-- 2. Webhook idempotency log (service role only) -------------------------------
create table public.stripe_events (
  id           text primary key,             -- Stripe event id (evt_...)
  type         text not null,
  company_id   uuid references public.companies(id) on delete set null,
  received_at  timestamptz not null default now(),
  processed_at timestamptz
);
alter table public.stripe_events enable row level security;   -- no policies: clients see nothing
revoke all on public.stripe_events from anon, authenticated;
-- Explicit, because default privileges differ between projects: the billing-test branch's
-- defaults give service_role no table rights (webhook failed: permission denied for table stripe_events).
grant select, insert, update, delete on public.stripe_events to service_role;

-- 3. Comp the 5 existing companies (ids read from the live project 2026-10-30) ---
update public.companies
   set is_comped = true,
       comped_reason = 'Grandfathered client before Stripe billing (2026-10-30)'
 where id in ('a643826b-ca0c-49ea-ac7f-7bbce193b8ee',   -- Spectrum Coach
              'aa1917a1-0c6a-4203-b7f1-1bf901b2ac81',   -- Hotondo Southcoast
              '6cb45fc4-9315-4c67-933f-5313c48495e0',   -- Hotondo Sapphire Coast
              'cc08d34a-7798-4f7a-b3dc-b21713d9c7e4',   -- Hotondo Southern Highlands
              'deaac889-e3ec-4275-87df-bb715ec02ebf');  -- Hotondo Port Maquarie

-- 4. Access functions -----------------------------------------------------------
create or replace function public.company_access(p_company uuid)
returns text
language sql stable security definer
set search_path to 'public'
as $$
  select case
    when c.id is null                                          then 'read_only'
    when c.is_comped                                           then 'comped'
    when c.subscription_status = 'active'                      then 'full'
    -- 1-day buffer so a late "trial ended" webhook never locks a paying customer out
    when c.subscription_status = 'trialing'
         and (c.trial_ends_at is null or c.trial_ends_at > now() - interval '1 day')
                                                               then 'full'
    when c.subscription_status = 'past_due'
         and coalesce(c.past_due_since, now()) > now() - interval '7 days'
                                                               then 'grace'
    else 'read_only'
  end
  from (select 1) one
  left join public.companies c on c.id = p_company;
$$;

create or replace function public.company_can_write(p_company uuid)
returns boolean
language sql stable security definer
set search_path to 'public'
as $$
  select public.is_platform_admin()
      or public.company_access(p_company) in ('comped','full','grace');
$$;

-- Billing summary for the signed-in user's current company (used by the UI).
create or replace function public.my_billing()
returns table(company_id uuid, plan text, seat_limit integer, seats_used integer,
              is_comped boolean, subscription_status text, access text,
              trial_ends_at timestamptz, current_period_end timestamptz,
              cancel_at_period_end boolean, past_due_since timestamptz,
              grace_ends_at timestamptz, has_customer boolean, can_manage boolean)
language sql stable security definer
set search_path to 'public'
as $$
  select c.id, c.plan, c.seat_limit, public.seats_used(c.id),
         c.is_comped, c.subscription_status, public.company_access(c.id),
         c.trial_ends_at, c.current_period_end, c.cancel_at_period_end, c.past_due_since,
         case when c.subscription_status = 'past_due'
              then coalesce(c.past_due_since, now()) + interval '7 days' end,
         c.stripe_customer_id is not null,
         public.is_manager()
    from public.companies c
   where c.id = public.auth_company_id();
$$;

revoke execute on function public.company_access(uuid)    from public, anon;
revoke execute on function public.company_can_write(uuid) from public, anon;
revoke execute on function public.my_billing()            from public, anon;
grant  execute on function public.company_access(uuid), public.company_can_write(uuid),
                           public.my_billing() to authenticated, service_role;

-- 5. Lock down plan / seats / Stripe fields on companies ------------------------
revoke update on public.companies from anon, authenticated;
grant  update (name, abn, address, phone, email, website, logo_url, brand_colour)
  on public.companies to authenticated;

create or replace function public.set_seat_limit(p_limit integer)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_used integer; v_comped boolean;
begin
  if not public.is_manager() then
    raise exception 'Only an owner or admin can change the seat limit.' using errcode='42501';
  end if;
  select c.is_comped into v_comped from public.companies c where c.id = public.auth_company_id();
  if not coalesce(v_comped, false) and not public.is_platform_admin() then
    raise exception 'Your seat limit comes from your plan. Upgrade your plan in Billing to add seats.'
      using errcode='42501';
  end if;
  if p_limit < 1 then raise exception 'Seat limit must be at least 1.' using errcode='22023'; end if;
  v_used := public.seats_used(public.auth_company_id());
  if p_limit < v_used then
    raise exception 'You already have % people. Remove someone before dropping to % seats.', v_used, p_limit
      using errcode='22023';
  end if;
  update public.companies set seat_limit = p_limit where id = public.auth_company_id();
  return p_limit;
end;
$function$;

-- 6. Read-only enforcement: restrictive policies (AND-ed with the existing ones) --
--    Only writes are restricted; there are deliberately no SELECT policies here.
do $$
declare t text; op text;
begin
  foreach t in array array['clients','tasks','dwellings','client_documents','invitations',
                           'sales_kpis','sales_kpi_rates'] loop
    foreach op in array array['insert','update','delete'] loop
      execute format(
        'create policy %I on public.%I as restrictive for %s to authenticated %s',
        'billing_write_' || op, t, op,
        case op
          when 'insert' then 'with check (public.company_can_write(company_id))'
          when 'update' then 'using (public.company_can_write(company_id)) with check (public.company_can_write(company_id))'
          else               'using (public.company_can_write(company_id))'
        end);
    end loop;
  end loop;
end $$;

-- 7. New sign-ups: non-invite companies start with no subscription --------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_token uuid; v_invite public.invitations%rowtype;
  v_company_id uuid; v_role public.user_role; v_company_nm text;
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

  return new;
end;
$function$;

-- 8. Companies the platform admin creates by hand start unpaid, like a sign-up (comp them explicitly)
CREATE OR REPLACE FUNCTION public.provision_company(p_company text, p_email text, p_seats integer DEFAULT 3, p_role user_role DEFAULT 'owner'::user_role, p_plan text DEFAULT 'team'::text)
 RETURNS TABLE(company_id uuid, company_name text, invite_email text, invite_role text, seats integer, invite_token uuid, added_directly boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_company uuid; v_token uuid; v_uid uuid;
        v_email text := lower(trim(p_email)); v_name text := trim(p_company);
begin
  perform public.require_platform_admin();
  if v_name = '' then raise exception 'Company name is required.'; end if;
  if v_email !~ '^[^@[:space:]<>]+@[^@[:space:]<>]+\.[^@[:space:]<>]+$' then
    raise exception 'Not a valid plain email address: %', p_email; end if;
  if p_seats < 1 then raise exception 'Seat count must be at least 1.'; end if;
  if exists (select 1 from public.companies c where lower(c.name) = lower(v_name)) then
    raise exception 'A company called "%" already exists.', v_name; end if;

  insert into public.companies (name, seat_limit, plan, subscription_status, is_comped)
  values (v_name, p_seats, p_plan, 'none', false)
  returning id into v_company;

  select u.id into v_uid from auth.users u where lower(u.email) = v_email;

  if v_uid is not null then
    insert into public.profiles (id, full_name, email, current_company_id)
    select v_uid, nullif(trim(u.raw_user_meta_data->>'full_name'),''), u.email, v_company
      from auth.users u where u.id = v_uid
    on conflict (id) do nothing;

    insert into public.company_members (user_id, company_id, role)
    values (v_uid, v_company, p_role);

    perform public.platform_log('company.create', v_name,
      jsonb_build_object('owner', v_email, 'seats', p_seats, 'existing_login', true));
    return query select v_company, v_name, v_email, p_role::text, p_seats, null::uuid, true;
  end if;

  insert into public.invitations (company_id, email, role)
  values (v_company, v_email, p_role) returning token into v_token;
  perform public.platform_log('company.create', v_name,
    jsonb_build_object('owner', v_email, 'seats', p_seats, 'existing_login', false));
  return query select v_company, v_name, v_email, p_role::text, p_seats, v_token, false;
end;
$function$;

-- 9. Platform admin: see billing state, and choose to comp a company --------------
create or replace function public.platform_company_billing()
returns table(company_id uuid, is_comped boolean, comped_reason text, subscription_status text,
              access text, trial_ends_at timestamptz, has_subscription boolean)
language sql stable security definer
set search_path to 'public'
as $$
  select c.id, c.is_comped, c.comped_reason, c.subscription_status, public.company_access(c.id),
         c.trial_ends_at, c.stripe_subscription_id is not null
    from public.companies c
   where (select public.is_platform_admin());
$$;

create or replace function public.platform_set_company_comped(p_company_id uuid, p_comped boolean,
                                                              p_reason text default null)
returns text
language plpgsql security definer
set search_path to 'public'
as $$
declare v_name text; v_status text; v_reason text := nullif(trim(p_reason), '');
begin
  perform public.require_platform_admin();
  select c.name, c.subscription_status into v_name, v_status from public.companies c where c.id = p_company_id;
  if v_name is null then raise exception 'No such company.'; end if;
  -- the webhook ignores comped companies, so comping a live subscription would keep billing them
  if p_comped and v_status in ('trialing','active','past_due','unpaid','paused') then
    raise exception '% has a Stripe subscription (%). Cancel it in Stripe first so they are not charged, then mark the company free.',
      v_name, v_status using errcode = '22023';
  end if;
  update public.companies
     set is_comped = p_comped,
         comped_reason = case when p_comped then coalesce(v_reason, 'Complimentary - set by platform admin') end
   where id = p_company_id;
  perform public.platform_log(case when p_comped then 'company.comp' else 'company.uncomp' end,
                              v_name, jsonb_build_object('reason', v_reason));
  return v_name || case when p_comped then ' is now complimentary (free).'
                        else ' is no longer free - they need a plan to keep editing.' end;
end;
$$;

revoke execute on function public.platform_company_billing()                          from public, anon;
revoke execute on function public.platform_set_company_comped(uuid, boolean, text)     from public, anon;
grant  execute on function public.platform_company_billing(),
                           public.platform_set_company_comped(uuid, boolean, text)     to authenticated;

commit;
