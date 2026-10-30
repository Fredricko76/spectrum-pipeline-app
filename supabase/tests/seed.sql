-- Local test seed (run BEFORE the migration, on top of local_stubs.sql + baseline/schema.sql).
alter table auth.users disable trigger on_auth_user_created;

insert into public.companies (id, name, plan, seat_limit) values
  ('a643826b-ca0c-49ea-ac7f-7bbce193b8ee','Spectrum Coach','enterprise',999),
  ('aa1917a1-0c6a-4203-b7f1-1bf901b2ac81','Hotondo Southcoast','team',5),
  ('6cb45fc4-9315-4c67-933f-5313c48495e0','Hotondo Sapphire Coast','team',5),
  ('cc08d34a-7798-4f7a-b3dc-b21713d9c7e4','Hotondo Southern Highlands','team',5),
  ('deaac889-e3ec-4275-87df-bb715ec02ebf','Hotondo Port Maquarie','team',6),
  ('00000000-0000-0000-0000-0000000000b1','Paid Builder Pty Ltd','solo',3);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000f00d','fred@example.test'),       -- platform admin + comped owner
  ('00000000-0000-0000-0000-0000000000a1','owner@paid.test'),
  ('00000000-0000-0000-0000-0000000000a2','rep@paid.test');
insert into public.profiles (id, full_name, email, current_company_id) values
  ('00000000-0000-0000-0000-00000000f00d','Fred','fred@example.test','aa1917a1-0c6a-4203-b7f1-1bf901b2ac81'),
  ('00000000-0000-0000-0000-0000000000a1','Paula Owner','owner@paid.test','00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000a2','Ray Rep','rep@paid.test','00000000-0000-0000-0000-0000000000b1');
insert into public.company_members (user_id, company_id, role) values
  ('00000000-0000-0000-0000-00000000f00d','aa1917a1-0c6a-4203-b7f1-1bf901b2ac81','owner'),
  ('00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000b1','owner'),
  ('00000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000b1','consultant');
insert into public.platform_admins (user_id, email) values ('00000000-0000-0000-0000-00000000f00d','fred@example.test');

insert into public.clients (company_id, owner_id, first_name, surname) values
  ('aa1917a1-0c6a-4203-b7f1-1bf901b2ac81','00000000-0000-0000-0000-00000000f00d','Comp','Client'),
  ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Paid','Client');

alter table auth.users enable trigger on_auth_user_created;
