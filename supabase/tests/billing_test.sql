-- Behaviour tests for the billing migration. Run after seed.sql + the migration.
-- Every check raises on failure; psql runs with ON_ERROR_STOP=1. All changes roll back.
\set QUIET on
begin;

create function pg_temp.ok(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond,false) then raise exception 'FAIL: %', msg; end if; raise notice 'PASS: %', msg; end $$;
grant execute on function pg_temp.ok(boolean, text) to authenticated;
-- expect a statement to fail with an error containing pat
create function pg_temp.fails(stmt text, pat text, msg text) returns void language plpgsql as $$
begin
  begin execute stmt;
  exception when others then
    if sqlerrm ilike '%'||pat||'%' then raise notice 'PASS: % (%)', msg, sqlerrm; return; end if;
    raise exception 'FAIL: % - wrong error: %', msg, sqlerrm;
  end;
  raise exception 'FAIL: % - statement succeeded', msg;
end $$;
grant execute on function pg_temp.fails(text, text, text) to authenticated;
-- rows affected by a statement (RLS turns blocked UPDATE/DELETE into 0 rows, not errors)
create function pg_temp.rows(stmt text) returns int language plpgsql as $$
declare n int; begin execute stmt; get diagnostics n = row_count; return n; end $$;
grant execute on function pg_temp.rows(text) to authenticated;

-- ---------------------------------------------------------------- setup checks (as postgres)
select pg_temp.ok((select count(*) = 5 from companies where is_comped), 'exactly the 5 existing companies are comped');
select pg_temp.ok((select bool_and(company_access(id) = 'comped') from companies where is_comped), 'comped companies get access=comped');
select pg_temp.ok((select plan = 'team' and seat_limit = 5 from companies where name = 'Hotondo Southcoast'), 'comped plan/seat values unchanged');
select pg_temp.ok((select subscription_status = 'none' and not is_comped from companies where name = 'Paid Builder Pty Ltd'), 'non-comped existing row defaults to none');

-- ---------------------------------------------------------------- comped owner behaves as today
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select pg_temp.ok((select access = 'comped' and is_comped from my_billing()), 'my_billing reports comped');
insert into clients (company_id, owner_id, first_name) values ('aa1917a1-0c6a-4203-b7f1-1bf901b2ac81', auth.uid(), 'New');
update clients set notes = 'edited' where company_id = 'aa1917a1-0c6a-4203-b7f1-1bf901b2ac81';
select pg_temp.ok((select count(*) = 2 from clients where company_id = 'aa1917a1-0c6a-4203-b7f1-1bf901b2ac81'), 'comped company can insert/update clients');
select pg_temp.ok(set_seat_limit(8) = 8, 'comped company can still change its own seats');
update companies set name = 'Hotondo Southcoast', brand_colour = '#112233' where id = 'aa1917a1-0c6a-4203-b7f1-1bf901b2ac81';
select pg_temp.ok(true, 'owner can still edit name/brand colour');
select pg_temp.fails($$update companies set seat_limit = 99 where id = auth_company_id()$$, 'permission denied', 'owner cannot write seat_limit directly');
select pg_temp.fails($$update companies set plan = 'network' where id = auth_company_id()$$, 'permission denied', 'owner cannot write plan directly');
select pg_temp.fails($$update companies set is_comped = true where id = auth_company_id()$$, 'permission denied', 'owner cannot write is_comped');
select pg_temp.fails($$update companies set subscription_status = 'active' where id = auth_company_id()$$, 'permission denied', 'owner cannot write subscription_status');
select pg_temp.fails($$select * from stripe_events$$, 'permission denied', 'stripe_events hidden from clients');
-- comped invite flow: invitation insert allowed
insert into invitations (company_id, email, role, invited_by) values ('aa1917a1-0c6a-4203-b7f1-1bf901b2ac81','new@comp.test','consultant', auth.uid());
select pg_temp.ok(true, 'comped company can create invitations');
reset role;

-- ---------------------------------------------------------------- 'none' company is read-only
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select access = 'read_only' and subscription_status = 'none' from my_billing()), 'none -> read_only');
select pg_temp.ok((select count(*) = 1 from clients), 'read_only: reads still work');
select pg_temp.fails($$insert into clients (company_id, owner_id, first_name) values (auth_company_id(), auth.uid(), 'X')$$, 'row-level security', 'read_only: insert client blocked');
select pg_temp.ok(pg_temp.rows($$update clients set notes = 'x' where true$$) = 0, 'read_only: update client blocked (0 rows)');
select pg_temp.ok(pg_temp.rows($$delete from clients where true$$) = 0, 'read_only: delete client blocked (0 rows)');
select pg_temp.fails($$insert into invitations (company_id, email, role, invited_by) values (auth_company_id(), 'x@paid.test', 'consultant', auth.uid())$$, 'row-level security', 'read_only: invitations blocked');
select pg_temp.fails($$select set_seat_limit(10)$$, 'comes from your plan', 'paid/none company cannot raise its own seats via RPC');
reset role;

-- ---------------------------------------------------------------- trialing -> full
update companies set subscription_status = 'trialing', trial_ends_at = now() + interval '14 days', plan = 'starter', seat_limit = 3
 where id = '00000000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select access = 'full' from my_billing()), 'trialing -> full');
insert into clients (company_id, owner_id, first_name) values (auth_company_id(), auth.uid(), 'Trial');
select pg_temp.ok(pg_temp.rows($$update clients set notes = 'trial' where true$$) = 2, 'trialing: insert + update allowed');
select pg_temp.fails($$select set_seat_limit(10)$$, 'comes from your plan', 'trialing company cannot raise its own seats');
select pg_temp.fails($$update companies set seat_limit = 10 where id = auth_company_id()$$, 'permission denied', 'trialing owner cannot write seat_limit directly');
reset role;
-- consultant in the same company also writes (own clients)
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';
insert into clients (company_id, owner_id, first_name) values (auth_company_id(), auth.uid(), 'Rep lead');
select pg_temp.ok(true, 'trialing: consultant can add own client');
reset role;

-- trial ended >1 day ago but webhook never arrived -> read_only
update companies set trial_ends_at = now() - interval '2 days' where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'read_only', 'stale trialing (ended >1 day) -> read_only');
update companies set trial_ends_at = now() - interval '2 hours' where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'full', 'trial ended <1 day ago (webhook lag buffer) -> still full');

-- ---------------------------------------------------------------- past_due grace
update companies set subscription_status = 'past_due', past_due_since = now() - interval '3 days' where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'grace', 'past_due 3 days -> grace');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select grace_ends_at::date = (now() + interval '4 days')::date from my_billing()), 'grace_ends_at = past_due_since + 7 days');
insert into clients (company_id, owner_id, first_name) values (auth_company_id(), auth.uid(), 'Grace');
select pg_temp.ok(true, 'grace: writes allowed');
reset role;
update companies set past_due_since = now() - interval '8 days' where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'read_only', 'past_due 8 days -> read_only');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.fails($$insert into clients (company_id, owner_id, first_name) values (auth_company_id(), auth.uid(), 'Late')$$, 'row-level security', 'past_due >7 days: insert blocked');
reset role;

-- ---------------------------------------------------------------- canceled -> read-only, data kept
update companies set subscription_status = 'canceled', past_due_since = null where id = '00000000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.ok((select access = 'read_only' from my_billing()), 'canceled -> read_only');
select pg_temp.ok((select count(*) = 4 from clients), 'canceled: all 4 clients still readable');
select pg_temp.ok(pg_temp.rows($$update clients set notes = 'x' where true$$) = 0, 'canceled: updates blocked');
select pg_temp.ok(pg_temp.rows($$delete from clients where true$$) = 0, 'canceled: deletes blocked');
reset role;
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'read_only', 'unpaid/canceled share read_only');
update companies set subscription_status = 'unpaid' where id = '00000000-0000-0000-0000-0000000000b1';
select pg_temp.ok(company_access('00000000-0000-0000-0000-0000000000b1') = 'read_only', 'unpaid -> read_only');

-- platform admin can still write into a read-only company (support)
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select pg_temp.ok(company_can_write('00000000-0000-0000-0000-0000000000b1'), 'platform admin bypass');
reset role;

-- ---------------------------------------------------------------- invite flow (active, seats 3)
update companies set subscription_status = 'active', seat_limit = 3 where id = '00000000-0000-0000-0000-0000000000b1';
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
insert into invitations (company_id, email, role, invited_by)
  values (auth_company_id(), 'third@paid.test', 'consultant', auth.uid()),
         (auth_company_id(), 'fourth@paid.test', 'consultant', auth.uid());
select pg_temp.ok(true, 'active company can create invitations');
reset role;
-- GoTrue inserts into auth.users with the invite token in metadata
insert into auth.users (email, raw_user_meta_data)
select 'third@paid.test', jsonb_build_object('full_name','Third','invite_token', token::text)
  from invitations where email = 'third@paid.test';
select pg_temp.ok((select count(*) = 3 from company_members where company_id = '00000000-0000-0000-0000-0000000000b1' and active), 'invite accepted: 3rd member joined');
select pg_temp.ok((select status = 'accepted' from invitations where email = 'third@paid.test'), 'invitation marked accepted');
select pg_temp.fails($$insert into auth.users (email, raw_user_meta_data)
  select 'fourth@paid.test', jsonb_build_object('invite_token', token::text) from invitations where email = 'fourth@paid.test'$$,
  'used all of its seats', 'invite beyond seat limit rejected');
-- comped company invite acceptance
insert into auth.users (email, raw_user_meta_data)
select 'new@comp.test', jsonb_build_object('invite_token', token::text) from invitations where email = 'new@comp.test';
select pg_temp.ok((select count(*) = 2 from company_members where company_id = 'aa1917a1-0c6a-4203-b7f1-1bf901b2ac81'), 'comped invite accepted');

-- ---------------------------------------------------------------- new self-serve sign-up
insert into auth.users (email, raw_user_meta_data) values ('newbuilder@x.test', '{"full_name":"New Builder","company_name":"New Homes Co"}');
select pg_temp.ok((select subscription_status = 'none' and not is_comped and company_access(id) = 'read_only' from companies where name = 'New Homes Co'),
  'non-invite sign-up -> status none, not comped, read_only');
select pg_temp.ok((select m.role = 'owner' from company_members m join companies c on c.id = m.company_id where c.name = 'New Homes Co'), 'sign-up user is owner');

-- ---------------------------------------------------------------- provision_company starts unpaid; comping is explicit
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select * from provision_company('Manual Builder', 'boss@manual.test', 4) \g /dev/null
reset role;
select pg_temp.ok((select not is_comped and subscription_status = 'none' and seat_limit = 4
                     and company_access(id) = 'read_only' from companies where name = 'Manual Builder'),
  'provision_company creates an unpaid (none, not comped, read_only) company');
select id as mb from companies where name = 'Manual Builder' \gset
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select pg_temp.ok((select count(*) >= 5 from platform_company_billing()), 'platform admin sees billing for every company');
select pg_temp.ok(platform_set_company_comped(:'mb', true, 'Mate rates')
                  like '%complimentary%', 'platform admin can comp a company');
reset role;
select pg_temp.ok((select is_comped and comped_reason = 'Mate rates' and company_access(id) = 'comped'
                     from companies where name = 'Manual Builder'), 'comped: access=comped, reason saved');
select pg_temp.ok((select count(*) = 1 from platform_audit where action = 'company.comp' and target = 'Manual Builder'), 'comp is audit-logged');
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select platform_set_company_comped(:'mb', false) \g /dev/null
reset role;
select pg_temp.ok((select not is_comped and comped_reason is null and company_access(id) = 'read_only'
                     from companies where name = 'Manual Builder'), 'un-comp: back to read_only');
-- live subscription (b1 is 'active' from the invite tests) cannot be comped: Stripe would keep billing
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-00000000f00d';
select pg_temp.fails($$select platform_set_company_comped('00000000-0000-0000-0000-0000000000b1', true)$$,
  'Cancel it in Stripe first', 'cannot comp a company with a live subscription');
reset role;
-- not a platform admin
set local role authenticated;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.fails($$select platform_set_company_comped(auth_company_id(), true)$$,
  'Platform administrator access required', 'owner cannot comp their own company');
select pg_temp.ok((select count(*) = 0 from platform_company_billing()), 'non-admin sees no platform billing rows');
reset role;
set local role anon;
select pg_temp.fails($$select platform_set_company_comped('00000000-0000-0000-0000-0000000000b1', true)$$,
  'permission denied', 'anon cannot call platform_set_company_comped');
reset role;

rollback;
\echo ALL BILLING TESTS PASSED
