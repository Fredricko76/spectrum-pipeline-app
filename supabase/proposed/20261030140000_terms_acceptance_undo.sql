-- Undo for 20261030140000_terms_acceptance.sql.
-- Restores handle_new_user() exactly as it was live on 2026-10-30, then drops the table.
-- Dropping the table deletes all acceptance records in it, so export them first if they're needed.
-- (The copy in auth.users.raw_user_meta_data is not affected.)

create or replace function public.handle_new_user()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
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

drop table if exists public.terms_acceptances;
