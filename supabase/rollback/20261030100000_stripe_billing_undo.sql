-- =============================================================================
-- UNDO for migrations/20261030100000_stripe_billing.sql
-- Restores the exact pre-billing state. WARNING: drops the Stripe columns, so any
-- customer/subscription ids stored in them are lost (they remain in Stripe).
-- =============================================================================
begin;

do $$
declare t text; op text;
begin
  foreach t in array array['clients','tasks','dwellings','client_documents','invitations',
                           'sales_kpis','sales_kpi_rates'] loop
    foreach op in array array['insert','update','delete'] loop
      execute format('drop policy if exists %I on public.%I', 'billing_write_' || op, t);
    end loop;
  end loop;
end $$;

-- restore table-level UPDATE exactly as before (Supabase default grants)
revoke update (name, abn, address, phone, email, website, logo_url, brand_colour)
  on public.companies from authenticated;
grant update on public.companies to anon, authenticated;

drop function if exists public.my_billing();
drop function if exists public.company_can_write(uuid);
drop function if exists public.company_access(uuid);
do $$ begin  -- undo the explicit grant (the drop below removes it too; kept explicit for clarity)
  if to_regclass('public.stripe_events') is not null then
    revoke select, insert, update, delete on public.stripe_events from service_role;
  end if;
end $$;
drop table if exists public.stripe_events;

-- original function bodies (verbatim from baseline/schema.sql)
CREATE OR REPLACE FUNCTION public.set_seat_limit(p_limit integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_used integer;
begin
  if not public.is_manager() then
    raise exception 'Only an owner or admin can change the seat limit.' using errcode='42501';
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
$function$
;
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
    insert into public.companies (name) values (v_company_nm) returning id into v_company_id;
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
$function$
;
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

  insert into public.companies (name, seat_limit, plan)
  values (v_name, p_seats, p_plan) returning id into v_company;

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
$function$
;

-- restore the original plan check; rows on the new plan names are mapped back first
update public.companies set plan = 'solo' where plan = 'starter';
update public.companies set plan = 'team' where plan = 'network';
alter table public.companies drop constraint companies_plan_check;
alter table public.companies add constraint companies_plan_check
  CHECK ((plan = ANY (ARRAY['solo'::text, 'team'::text, 'enterprise'::text])));

alter table public.companies
  drop constraint if exists companies_subscription_status_check,
  drop constraint if exists companies_stripe_subscription_id_key,
  drop constraint if exists companies_stripe_customer_id_key,
  drop column if exists comped_reason,
  drop column if exists is_comped,
  drop column if exists billing_updated_at,
  drop column if exists past_due_since,
  drop column if exists cancel_at_period_end,
  drop column if exists current_period_end,
  drop column if exists trial_ends_at,
  drop column if exists subscription_status,
  drop column if exists stripe_price_id,
  drop column if exists stripe_subscription_id,
  drop column if exists stripe_customer_id;

commit;
