-- Local test for proposed/20261031150000_lead_connections.sql (run via tests/run_lead_connections.sh).
-- Uses the seed users: Paula Owner (owner, Paid Builder), Ray Rep (consultant, Paid Builder),
-- Fred (owner, Hotondo Southcoast).
\set paula '00000000-0000-0000-0000-0000000000a1'
\set ray   '00000000-0000-0000-0000-0000000000a2'
\set fred  '00000000-0000-0000-0000-00000000f00d'
-- give Paid Builder a live plan so it can write
update public.companies set subscription_status = 'active', is_comped = false where id = '00000000-0000-0000-0000-0000000000b1';

create temp table r(k text, v text);
grant all on r to authenticated;

set role authenticated;
-- 1. table itself still closed to signed-in users
select set_config('request.jwt.claim.sub', :'paula', false);
do $$ begin
  perform 1 from public.lead_sources; raise notice 'FAIL table readable';
exception when insufficient_privilege then raise notice 'PASS table not readable by authenticated'; end $$;

-- 2. owner creates website + google; double create returns same id
insert into r select 'web1', public.lead_source_create('Website','Australia/Melbourne')::text;
insert into r select 'web2', public.lead_source_create('Website')::text;
insert into r select 'goo',  public.lead_source_create('Google','Not/AZone')::text;
do $$ begin
  if (select v from r where k='web1') = (select v from r where k='web2') then raise notice 'PASS create is idempotent per channel';
  else raise notice 'FAIL duplicate key created'; end if;
  if (select count(*) from public.my_lead_sources()) = 2 then raise notice 'PASS owner sees 2 connections'; else raise notice 'FAIL owner count'; end if;
  if (select timezone from public.my_lead_sources() where channel='Website') = 'Australia/Melbourne'
     and (select timezone from public.my_lead_sources() where channel='Google') = 'Australia/Sydney'
  then raise notice 'PASS timezone validated'; else raise notice 'FAIL timezone'; end if;
  if (select site_key from public.my_lead_sources() where channel='Website') ~ '^lk_[0-9a-f]{48}$' then raise notice 'PASS key format'; else raise notice 'FAIL key format'; end if;
  if (select default_owner_name from public.my_lead_sources() where channel='Website') = 'Paula Owner' then raise notice 'PASS default owner is creator'; else raise notice 'FAIL default owner'; end if;
  begin perform public.lead_source_create('Other'); raise notice 'FAIL bad channel accepted';
  exception when invalid_parameter_value then raise notice 'PASS bad channel refused'; end;
end $$;
insert into r select 'oldkey', site_key from public.my_lead_sources() where channel='Website';
select public.lead_source_regenerate((select v::uuid from r where k='web1'));
do $$ begin
  if (select site_key from public.my_lead_sources() where channel='Website') <> (select v from r where k='oldkey') then raise notice 'PASS regenerate changes key'; else raise notice 'FAIL regenerate'; end if;
end $$;
-- reassign to Ray (active member) ok; to Fred (other company) refused; switch off/on
select public.lead_source_update((select v::uuid from r where k='web1'), '00000000-0000-0000-0000-0000000000a2', null);
do $$ begin
  if (select default_owner_id from public.my_lead_sources() where channel='Website') = '00000000-0000-0000-0000-0000000000a2' then raise notice 'PASS reassign to member'; else raise notice 'FAIL reassign'; end if;
  begin perform public.lead_source_update((select v::uuid from r where k='web1'), '00000000-0000-0000-0000-00000000f00d', null); raise notice 'FAIL outsider owner accepted';
  exception when invalid_parameter_value then raise notice 'PASS outsider owner refused'; end;
  perform public.lead_source_update((select v::uuid from r where k='web1'), null, false);
  if not (select active from public.my_lead_sources() where channel='Website') then raise notice 'PASS switch off'; else raise notice 'FAIL switch off'; end if;
  perform public.lead_source_create('Website');
  if (select active from public.my_lead_sources() where channel='Website') then raise notice 'PASS create switches back on'; else raise notice 'FAIL reactivate'; end if;
end $$;

-- 3. consultant in same company: sees nothing, cannot create/regenerate
select set_config('request.jwt.claim.sub', :'ray', false);
do $$ begin
  if (select count(*) from public.my_lead_sources()) = 0 then raise notice 'PASS consultant sees nothing'; else raise notice 'FAIL consultant sees keys'; end if;
  begin perform public.lead_source_create('Meta'); raise notice 'FAIL consultant created';
  exception when insufficient_privilege then raise notice 'PASS consultant cannot create'; end;
  begin perform public.lead_source_regenerate((select v::uuid from r where k='web1')); raise notice 'FAIL consultant regenerated';
  exception when insufficient_privilege then raise notice 'PASS consultant cannot regenerate'; end;
end $$;

-- 4. owner of another company: sees none of Paid Builder's keys, cannot touch them
select set_config('request.jwt.claim.sub', :'fred', false);
do $$ begin
  if (select count(*) from public.my_lead_sources()) = 0 then raise notice 'PASS other company sees none'; else raise notice 'FAIL cross-company leak'; end if;
  begin perform public.lead_source_regenerate((select v::uuid from r where k='web1')); raise notice 'FAIL cross-company regenerate';
  exception when no_data_found then raise notice 'PASS cross-company regenerate refused'; end;
  begin perform public.lead_source_update((select v::uuid from r where k='web1'), null, false); raise notice 'FAIL cross-company update';
  exception when no_data_found then raise notice 'PASS cross-company update refused'; end;
end $$;

-- 5. anon cannot call at all
reset role; set role anon;
do $$ begin
  perform public.my_lead_sources(); raise notice 'FAIL anon can list';
exception when insufficient_privilege then raise notice 'PASS anon cannot call'; end $$;
reset role;

-- 6. read-only company cannot create (but can still regenerate)
update public.companies set subscription_status = 'canceled', is_comped = false where id = '00000000-0000-0000-0000-0000000000b1';
set role authenticated;
select set_config('request.jwt.claim.sub', :'paula', false);
do $$ begin
  if public.company_can_write('00000000-0000-0000-0000-0000000000b1') then raise notice 'SKIP read-only setup did not take'; return; end if;
  begin perform public.lead_source_create('Meta'); raise notice 'FAIL read-only created';
  exception when insufficient_privilege then raise notice 'PASS read-only cannot create'; end;
  perform public.lead_source_regenerate((select v::uuid from r where k='web1'));
  raise notice 'PASS read-only can still regenerate';
end $$;
reset role;
