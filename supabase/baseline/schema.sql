-- Baseline: reconstructed end state of the live public schema of Supabase project
-- qjkmkmmrgtoaocygymqo (Sydney), read-only from the system catalog on 2026-10-30
-- (58 migrations applied, last: 20261025043207 disable_chat; see live_migrations.txt).
-- Contains: enum, tables, constraints, indexes, RLS flags, every public function,
-- triggers (incl. auth.users -> handle_new_user), RLS policies, function revokes and
-- table grants for anon/authenticated. No data.
-- Purpose: local testing of new migrations. It is NOT a migration and must never be
-- applied to the live project. Function revokes "from public" are approximated.
set check_function_bodies = off;

create type public.user_role as enum ('owner', 'admin', 'consultant');
create sequence if not exists public.platform_audit_id_seq;
create table public.chat_conversations (
  id uuid default gen_random_uuid() not null,
  kind text not null,
  user_a uuid,
  user_b uuid,
  company_a uuid,
  company_b uuid,
  created_by uuid not null,
  created_at timestamp with time zone default now() not null
);
create table public.chat_reads (
  user_id uuid not null,
  conversation_id uuid default '00000000-0000-0000-0000-000000000000'::uuid not null,
  last_read_at timestamp with time zone default now() not null
);
create table public.client_documents (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  client_id uuid not null,
  file_name text not null,
  storage_path text not null,
  mime_type text,
  size_bytes bigint,
  uploaded_by uuid,
  uploaded_at timestamp with time zone default now() not null,
  deleted_at timestamp with time zone,
  deleted_by uuid
);
create table public.client_events (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  client_id uuid not null,
  from_stage text,
  to_stage text not null,
  presentation_type text,
  owner_id uuid,
  changed_by uuid,
  changed_at timestamp with time zone default now() not null
);
create table public.clients (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  owner_id uuid,
  created_by uuid,
  first_name text default ''::text not null,
  surname text default ''::text not null,
  email text,
  phone text,
  enquiry_date date,
  build_type text,
  buyer_type text,
  forecast_month text,
  stage text default 'New Enquiry'::text not null,
  next_stage text,
  presentation_type text,
  next_action_date date,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  next_presentation_type text,
  budget numeric(12,2),
  timing text,
  appointment_date date,
  discovery_date date,
  presentation_date date,
  review_date date,
  won_date date,
  lost_date date,
  lead_source text,
  external_lead_id text
);
create table public.companies (
  id uuid default gen_random_uuid() not null,
  name text not null,
  abn text,
  address text,
  phone text,
  email text,
  website text,
  logo_url text,
  brand_colour text default '#1E3A8A'::text not null,
  plan text default 'solo'::text not null,
  seat_limit integer default 3 not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);
create table public.company_members (
  user_id uuid not null,
  company_id uuid not null,
  role user_role default 'consultant'::user_role not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  sales_reports_access boolean default false not null
);
create table public.dwellings (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  client_id uuid not null,
  label text,
  street_no text,
  street_name text,
  suburb text,
  estate text,
  stage text,
  notes text,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  "position" integer default 0 not null
);
create table public.invitations (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  email text not null,
  role user_role default 'consultant'::user_role not null,
  token uuid default gen_random_uuid() not null,
  status text default 'pending'::text not null,
  invited_by uuid,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '14 days'::interval) not null,
  accepted_at timestamp with time zone
);
create table public.lead_sources (
  id uuid default gen_random_uuid() not null,
  label text not null,
  site_key text not null,
  company_id uuid not null,
  default_owner_id uuid,
  allowed_host text,
  timezone text default 'Australia/Sydney'::text not null,
  active boolean default true not null,
  created_at timestamp with time zone default now() not null,
  channel text default 'Website'::text not null
);
create table public.platform_admins (
  user_id uuid not null,
  email text,
  added_at timestamp with time zone default now() not null
);
create table public.platform_audit (
  id bigint default nextval('platform_audit_id_seq'::regclass) not null,
  actor_id uuid,
  actor_email text,
  action text not null,
  target text,
  detail jsonb,
  at timestamp with time zone default now() not null
);
create table public.platform_messages (
  id uuid default gen_random_uuid() not null,
  sender_id uuid not null,
  sender_name text default ''::text not null,
  company_id uuid,
  company_name text default ''::text not null,
  body text not null,
  created_at timestamp with time zone default now() not null,
  conversation_id uuid
);
create table public.profiles (
  id uuid not null,
  full_name text,
  email text,
  created_at timestamp with time zone default now() not null,
  current_company_id uuid,
  company_id uuid,
  role user_role,
  active boolean default true not null,
  chat_enabled boolean default true not null
);
create table public.sales_kpi_rates (
  company_id uuid not null,
  owner_id uuid not null,
  year integer not null,
  lead_to_discovery numeric(5,2),
  discovery_to_presentation numeric(5,2),
  presentation_to_review numeric(5,2),
  review_to_won numeric(5,2),
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);
create table public.sales_kpis (
  company_id uuid not null,
  owner_id uuid not null,
  month date not null,
  leads integer default 0 not null,
  discovery integer default 0 not null,
  presentation integer default 0 not null,
  review integer default 0 not null,
  won integer default 0 not null,
  updated_by uuid,
  updated_at timestamp with time zone default now() not null
);
create table public.tasks (
  id uuid default gen_random_uuid() not null,
  company_id uuid not null,
  client_id uuid not null,
  title text not null,
  due_date date,
  done boolean default false not null,
  done_at timestamp with time zone,
  created_by uuid,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null
);
alter table public.chat_conversations add constraint chat_conv_shape CHECK ((((kind = 'dm'::text) AND (user_a IS NOT NULL) AND (user_b IS NOT NULL) AND (user_a <> user_b) AND (company_a IS NULL) AND (company_b IS NULL)) OR ((kind = 'team'::text) AND (company_a IS NOT NULL) AND (company_b IS NOT NULL) AND (company_a <> company_b) AND (user_a IS NULL) AND (user_b IS NULL))));
alter table public.chat_conversations add constraint chat_conversations_kind_check CHECK ((kind = ANY (ARRAY['dm'::text, 'team'::text])));
alter table public.chat_conversations add constraint chat_conversations_kind_company_a_company_b_key UNIQUE (kind, company_a, company_b);
alter table public.chat_conversations add constraint chat_conversations_kind_user_a_user_b_key UNIQUE (kind, user_a, user_b);
alter table public.chat_conversations add constraint chat_conversations_pkey PRIMARY KEY (id);
alter table public.chat_reads add constraint chat_reads_pkey PRIMARY KEY (user_id, conversation_id);
alter table public.client_documents add constraint client_documents_pkey PRIMARY KEY (id);
alter table public.client_events add constraint client_events_pkey PRIMARY KEY (id, company_id);
alter table public.clients add constraint clients_budget_check CHECK (((budget IS NULL) OR (budget >= (0)::numeric)));
alter table public.clients add constraint clients_build_type_check CHECK ((build_type = ANY (ARRAY['Standard Plans'::text, 'Modified Standard Plans'::text, 'House and Land'::text, 'Custom Plans'::text, 'Design and Construct'::text, 'Knockdown Rebuild'::text, 'Renovation / Extension'::text, 'Dual Occupancy'::text])));
alter table public.clients add constraint clients_buyer_type_check CHECK ((buyer_type = ANY (ARRAY['First Home Buyer'::text, 'Investor'::text, 'Owner Occupied'::text])));
alter table public.clients add constraint clients_lead_source_check CHECK (((lead_source IS NULL) OR (lead_source = ANY (ARRAY['Website'::text, 'Meta'::text, 'Google'::text, 'Referral'::text, 'Walk-in'::text, 'Display Home'::text, 'Phone'::text, 'Other'::text]))));
alter table public.clients add constraint clients_next_presentation_type_check CHECK ((next_presentation_type = ANY (ARRAY['Estimate'::text, 'Plans'::text, 'Estimate and Plans'::text])));
alter table public.clients add constraint clients_next_stage_check CHECK ((next_stage = ANY (ARRAY['New Enquiry'::text, 'Initial Contact'::text, 'Discovery Appointment'::text, 'Presentation Appointment'::text, 'Review / Closing'::text, 'Won'::text, 'Lost'::text, 'Sales Completed'::text])));
alter table public.clients add constraint clients_pkey PRIMARY KEY (id, company_id);
alter table public.clients add constraint clients_presentation_type_check CHECK ((presentation_type = ANY (ARRAY['Estimate'::text, 'Plans'::text, 'Estimate and Plans'::text])));
alter table public.clients add constraint clients_stage_check CHECK ((stage = ANY (ARRAY['New Enquiry'::text, 'Initial Contact'::text, 'Discovery Appointment'::text, 'Presentation Appointment'::text, 'Review / Closing'::text, 'Won'::text, 'Lost'::text])));
alter table public.clients add constraint clients_timing_check CHECK (((timing IS NULL) OR (timing = ANY (ARRAY['Within 3 months'::text, 'Within 6 months'::text, 'Within 9 months'::text, '9+ months'::text]))));
alter table public.companies add constraint companies_pkey PRIMARY KEY (id);
alter table public.companies add constraint companies_plan_check CHECK ((plan = ANY (ARRAY['solo'::text, 'team'::text, 'enterprise'::text])));
alter table public.companies add constraint companies_seat_limit_check CHECK ((seat_limit > 0));
alter table public.company_members add constraint company_members_pkey PRIMARY KEY (user_id, company_id);
alter table public.dwellings add constraint dwellings_pkey PRIMARY KEY (id, company_id);
alter table public.dwellings add constraint dwellings_stage_check CHECK ((stage = ANY (ARRAY['New Enquiry'::text, 'Initial Contact'::text, 'Discovery Appointment'::text, 'Presentation Appointment'::text, 'Review / Closing'::text, 'Won'::text, 'Lost'::text])));
alter table public.invitations add constraint invitations_pkey PRIMARY KEY (id);
alter table public.invitations add constraint invitations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'accepted'::text, 'revoked'::text])));
alter table public.invitations add constraint invitations_token_key UNIQUE (token);
alter table public.lead_sources add constraint lead_sources_channel_check CHECK ((channel = ANY (ARRAY['Website'::text, 'Meta'::text, 'Google'::text, 'Other'::text])));
alter table public.lead_sources add constraint lead_sources_pkey PRIMARY KEY (id);
alter table public.lead_sources add constraint lead_sources_site_key_key UNIQUE (site_key);
alter table public.platform_admins add constraint platform_admins_pkey PRIMARY KEY (user_id);
alter table public.platform_audit add constraint platform_audit_pkey PRIMARY KEY (id);
alter table public.platform_messages add constraint platform_messages_body_check CHECK (((btrim(body) <> ''::text) AND (length(body) <= 2000)));
alter table public.platform_messages add constraint platform_messages_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.sales_kpi_rates add constraint sales_kpi_rates_discovery_to_presentation_check CHECK (((discovery_to_presentation > (0)::numeric) AND (discovery_to_presentation <= (100)::numeric)));
alter table public.sales_kpi_rates add constraint sales_kpi_rates_lead_to_discovery_check CHECK (((lead_to_discovery > (0)::numeric) AND (lead_to_discovery <= (100)::numeric)));
alter table public.sales_kpi_rates add constraint sales_kpi_rates_pkey PRIMARY KEY (company_id, owner_id, year);
alter table public.sales_kpi_rates add constraint sales_kpi_rates_presentation_to_review_check CHECK (((presentation_to_review > (0)::numeric) AND (presentation_to_review <= (100)::numeric)));
alter table public.sales_kpi_rates add constraint sales_kpi_rates_review_to_won_check CHECK (((review_to_won > (0)::numeric) AND (review_to_won <= (100)::numeric)));
alter table public.sales_kpi_rates add constraint sales_kpi_rates_year_check CHECK (((year >= 2000) AND (year <= 2100)));
alter table public.sales_kpis add constraint sales_kpis_discovery_check CHECK ((discovery >= 0));
alter table public.sales_kpis add constraint sales_kpis_leads_check CHECK ((leads >= 0));
alter table public.sales_kpis add constraint sales_kpis_month_check CHECK ((EXTRACT(day FROM month) = (1)::numeric));
alter table public.sales_kpis add constraint sales_kpis_pkey PRIMARY KEY (company_id, owner_id, month);
alter table public.sales_kpis add constraint sales_kpis_presentation_check CHECK ((presentation >= 0));
alter table public.sales_kpis add constraint sales_kpis_review_check CHECK ((review >= 0));
alter table public.sales_kpis add constraint sales_kpis_won_check CHECK ((won >= 0));
alter table public.tasks add constraint tasks_pkey PRIMARY KEY (id, company_id);
alter table public.chat_conversations add constraint chat_conversations_company_a_fkey FOREIGN KEY (company_a) REFERENCES companies(id);
alter table public.chat_conversations add constraint chat_conversations_company_b_fkey FOREIGN KEY (company_b) REFERENCES companies(id);
alter table public.chat_conversations add constraint chat_conversations_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.chat_conversations add constraint chat_conversations_user_a_fkey FOREIGN KEY (user_a) REFERENCES auth.users(id);
alter table public.chat_conversations add constraint chat_conversations_user_b_fkey FOREIGN KEY (user_b) REFERENCES auth.users(id);
alter table public.chat_reads add constraint chat_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.client_documents add constraint client_documents_client_id_company_id_fkey FOREIGN KEY (client_id, company_id) REFERENCES clients(id, company_id) ON DELETE CASCADE;
alter table public.client_documents add constraint client_documents_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.client_documents add constraint client_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.client_events add constraint client_events_changed_by_fkey FOREIGN KEY (changed_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.client_events add constraint client_events_client_id_company_id_fkey FOREIGN KEY (client_id, company_id) REFERENCES clients(id, company_id) ON DELETE CASCADE;
alter table public.client_events add constraint client_events_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.clients add constraint clients_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.clients add constraint clients_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.clients add constraint clients_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.company_members add constraint company_members_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.company_members add constraint company_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.dwellings add constraint dwellings_client_id_company_id_fkey FOREIGN KEY (client_id, company_id) REFERENCES clients(id, company_id) ON DELETE CASCADE;
alter table public.dwellings add constraint dwellings_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.invitations add constraint invitations_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.invitations add constraint invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.lead_sources add constraint lead_sources_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.lead_sources add constraint lead_sources_default_owner_id_fkey FOREIGN KEY (default_owner_id) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.platform_admins add constraint platform_admins_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.platform_messages add constraint platform_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id);
alter table public.platform_messages add constraint platform_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.profiles add constraint profiles_current_company_id_fkey FOREIGN KEY (current_company_id) REFERENCES companies(id) ON DELETE SET NULL;
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.sales_kpi_rates add constraint sales_kpi_rates_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.sales_kpi_rates add constraint sales_kpi_rates_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.sales_kpi_rates add constraint sales_kpi_rates_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.sales_kpis add constraint sales_kpis_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.sales_kpis add constraint sales_kpis_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES profiles(id) ON DELETE CASCADE;
alter table public.sales_kpis add constraint sales_kpis_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES profiles(id) ON DELETE SET NULL;
alter table public.tasks add constraint tasks_client_id_company_id_fkey FOREIGN KEY (client_id, company_id) REFERENCES clients(id, company_id) ON DELETE CASCADE;
alter table public.tasks add constraint tasks_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies(id) ON DELETE CASCADE;
alter table public.tasks add constraint tasks_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id) ON DELETE SET NULL;
CREATE INDEX client_documents_client_idx ON public.client_documents USING btree (client_id) WHERE (deleted_at IS NULL);
CREATE INDEX client_documents_company_idx ON public.client_documents USING btree (company_id);
CREATE INDEX client_events_client ON public.client_events USING btree (company_id, client_id);
CREATE INDEX client_events_co_stage ON public.client_events USING btree (company_id, to_stage, changed_at);
CREATE INDEX client_events_co_when ON public.client_events USING btree (company_id, changed_at);
CREATE INDEX clients_action_idx ON public.clients USING btree (company_id, next_action_date);
CREATE INDEX clients_company_idx ON public.clients USING btree (company_id);
CREATE INDEX clients_owner_idx ON public.clients USING btree (company_id, owner_id);
CREATE INDEX clients_stage_idx ON public.clients USING btree (company_id, stage);
CREATE INDEX company_members_company_idx ON public.company_members USING btree (company_id) WHERE active;
CREATE INDEX company_members_user_idx ON public.company_members USING btree (user_id) WHERE active;
CREATE INDEX dwellings_client_idx ON public.dwellings USING btree (company_id, client_id);
CREATE INDEX dwellings_position_idx ON public.dwellings USING btree (company_id, client_id, "position");
CREATE INDEX invitations_company_idx ON public.invitations USING btree (company_id);
CREATE INDEX invitations_token_idx ON public.invitations USING btree (token);
CREATE INDEX platform_messages_conversation_idx ON public.platform_messages USING btree (conversation_id, created_at);
CREATE INDEX platform_messages_created_at_idx ON public.platform_messages USING btree (created_at);
CREATE INDEX tasks_client_idx ON public.tasks USING btree (company_id, client_id);
CREATE INDEX tasks_due_idx ON public.tasks USING btree (company_id, done, due_date);
CREATE UNIQUE INDEX clients_company_external_lead_uidx ON public.clients USING btree (company_id, external_lead_id) WHERE (external_lead_id IS NOT NULL);
alter table public.chat_conversations enable row level security;
alter table public.chat_reads enable row level security;
alter table public.client_documents enable row level security;
alter table public.client_events enable row level security;
alter table public.clients enable row level security;
alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.dwellings enable row level security;
alter table public.invitations enable row level security;
alter table public.lead_sources enable row level security;
alter table public.platform_admins enable row level security;
alter table public.platform_audit enable row level security;
alter table public.platform_messages enable row level security;
alter table public.profiles enable row level security;
alter table public.sales_kpi_rates enable row level security;
alter table public.sales_kpis enable row level security;
alter table public.tasks enable row level security;

CREATE OR REPLACE FUNCTION public.auth_company_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    -- the company they have selected, if the membership is still live
    (select m.company_id
       from public.company_members m
      where m.user_id = auth.uid()
        and m.active
        and m.company_id = (select p.current_company_id
                              from public.profiles p where p.id = auth.uid())),
    -- otherwise fall back to their oldest live membership
    (select m.company_id
       from public.company_members m
      where m.user_id = auth.uid() and m.active
      order by m.created_at, m.company_id
      limit 1)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.auth_role()
 RETURNS user_role
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select m.role
    from public.company_members m
   where m.user_id = auth.uid()
     and m.active
     and m.company_id = public.auth_company_id();
$function$
;

CREATE OR REPLACE FUNCTION public.can_manage_sales_reports()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select m.role = 'owner' or (m.role = 'admin' and m.sales_reports_access)
       from public.company_members m
      where m.user_id = auth.uid() and m.active
        and m.company_id = public.auth_company_id()),
    false);
$function$
;

CREATE OR REPLACE FUNCTION public.can_reach_client(p_client_id uuid, p_company_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1
    from public.clients c
    where c.id = p_client_id
      and c.company_id = p_company_id
      and c.company_id = public.auth_company_id()
      and (public.is_manager() or c.owner_id = auth.uid())
  );
$function$
;

CREATE OR REPLACE FUNCTION public.can_see_conversation(p_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.chat_conversations c
    where c.id = p_conversation_id
      and (
        (c.kind = 'dm' and auth.uid() in (c.user_a, c.user_b))
        or
        (c.kind = 'team' and public.auth_company_id() in (c.company_a, c.company_b))
      )
  );
$function$
;

CREATE OR REPLACE FUNCTION public.can_view_sales_reports()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select m.role = 'owner' or (m.role in ('admin','consultant') and m.sales_reports_access)
       from public.company_members m
      where m.user_id = auth.uid() and m.active
        and m.company_id = public.auth_company_id()),
    false);
$function$
;

CREATE OR REPLACE FUNCTION public.chat_mark_read(p_conversation_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_conv uuid := coalesce(p_conversation_id, '00000000-0000-0000-0000-000000000000'::uuid);
begin
  if p_conversation_id is not null and not public.can_see_conversation(p_conversation_id) then
    raise exception 'You are not part of that conversation.' using errcode='42501';
  end if;
  insert into public.chat_reads(user_id, conversation_id, last_read_at)
  values (auth.uid(), v_conv, now())
  on conflict (user_id, conversation_id) do update set last_read_at = excluded.last_read_at;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_my_conversations()
 RETURNS TABLE(conversation_id uuid, kind text, title text, last_body text, last_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    c.id, c.kind,
    case when c.kind = 'dm'
      then (select coalesce(nullif(p.full_name,''), split_part(p.email,'@',1))
              from public.profiles p where p.id = (case when c.user_a = auth.uid() then c.user_b else c.user_a end))
      else (select name from public.companies co
              where co.id = (case when c.company_a = public.auth_company_id() then c.company_b else c.company_a end))
    end,
    lm.body, lm.created_at
  from public.chat_conversations c
  left join lateral (
    select body, created_at from public.platform_messages
     where conversation_id = c.id order by created_at desc limit 1
  ) lm on true
  where (c.kind='dm' and auth.uid() in (c.user_a, c.user_b))
     or (c.kind='team' and public.auth_company_id() in (c.company_a, c.company_b))
  order by coalesce(lm.created_at, c.created_at) desc;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_people_directory()
 RETURNS TABLE(user_id uuid, full_name text, company_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, coalesce(nullif(p.full_name,''), split_part(p.email,'@',1)), c.name
  from public.profiles p
  left join public.companies c on c.id = p.company_id
  where p.chat_enabled = true
    and p.id <> auth.uid()
    and exists (select 1 from public.company_members m where m.user_id = p.id and m.active)
  order by c.name nulls last, full_name;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_start_dm(p_other_user uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_a uuid; v_b uuid; v_target_ok boolean; v_mine_ok boolean;
begin
  if p_other_user = auth.uid() then
    raise exception 'You cannot start a chat with yourself.' using errcode='22023';
  end if;
  select chat_enabled into v_target_ok from public.profiles where id = p_other_user;
  if v_target_ok is null then
    raise exception 'That person could not be found.' using errcode='22023';
  end if;
  if not v_target_ok then
    raise exception 'That person has chat turned off.' using errcode='42501';
  end if;
  select coalesce(chat_enabled,false) into v_mine_ok from public.profiles where id = auth.uid();
  if not v_mine_ok then
    raise exception 'Your chat access is turned off.' using errcode='42501';
  end if;

  v_a := least(auth.uid(), p_other_user);
  v_b := greatest(auth.uid(), p_other_user);

  select id into v_id from public.chat_conversations where kind='dm' and user_a=v_a and user_b=v_b;
  if v_id is null then
    insert into public.chat_conversations(kind, user_a, user_b, created_by)
    values ('dm', v_a, v_b, auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_start_team(p_company_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_mine uuid; v_a uuid; v_b uuid; v_target_ok boolean; v_mine_ok boolean;
begin
  v_mine := public.auth_company_id();
  if v_mine is null then
    raise exception 'You are not currently in a company.' using errcode='42501';
  end if;
  if p_company_id = v_mine then
    raise exception 'That is your own team.' using errcode='22023';
  end if;
  if not exists (select 1 from public.companies where id = p_company_id) then
    raise exception 'That company could not be found.' using errcode='22023';
  end if;
  select coalesce(chat_enabled,false) into v_mine_ok from public.profiles where id = auth.uid();
  if not v_mine_ok then
    raise exception 'Your chat access is turned off.' using errcode='42501';
  end if;
  select exists (
    select 1 from public.company_members m
    join public.profiles p on p.id = m.user_id
    where m.company_id = p_company_id and m.active and p.chat_enabled
  ) into v_target_ok;
  if not v_target_ok then
    raise exception 'That team does not have chat turned on.' using errcode='42501';
  end if;

  v_a := least(v_mine, p_company_id);
  v_b := greatest(v_mine, p_company_id);

  select id into v_id from public.chat_conversations where kind='team' and company_a=v_a and company_b=v_b;
  if v_id is null then
    insert into public.chat_conversations(kind, company_a, company_b, created_by)
    values ('team', v_a, v_b, auth.uid())
    returning id into v_id;
  end if;
  return v_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_teams_directory()
 RETURNS TABLE(company_id uuid, company_name text, chat_enabled_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, count(*) filter (where p.chat_enabled and m.active)::int
  from public.companies c
  join public.company_members m on m.company_id = c.id
  join public.profiles p on p.id = m.user_id
  where c.id <> coalesce(public.auth_company_id(), '00000000-0000-0000-0000-000000000000'::uuid)
  group by c.id, c.name
  having count(*) filter (where p.chat_enabled and m.active) > 0
  order by c.name;
$function$
;

CREATE OR REPLACE FUNCTION public.chat_unread_summary()
 RETURNS TABLE(conversation_id uuid, kind text, unread_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with mine as (
    select conversation_id, last_read_at from public.chat_reads where user_id = auth.uid()
  ),
  everyone_unread as (
    select null::uuid as conversation_id, 'everyone'::text as kind, count(*)::int as unread_count
    from public.platform_messages m
    where m.conversation_id is null
      and m.sender_id <> auth.uid()
      and m.created_at > coalesce(
        (select last_read_at from mine where conversation_id = '00000000-0000-0000-0000-000000000000'::uuid),
        '-infinity'::timestamptz)
  ),
  convo_unread as (
    select c.id as conversation_id, c.kind, count(m.id)::int as unread_count
    from public.chat_conversations c
    join public.platform_messages m
      on m.conversation_id = c.id and m.sender_id <> auth.uid()
     and m.created_at > coalesce((select last_read_at from mine where conversation_id = c.id), '-infinity'::timestamptz)
    where (c.kind='dm' and auth.uid() in (c.user_a, c.user_b))
       or (c.kind='team' and public.auth_company_id() in (c.company_a, c.company_b))
    group by c.id, c.kind
  )
  select * from everyone_unread
  union all
  select * from convo_unread;
$function$
;

CREATE OR REPLACE FUNCTION public.company_has_other_owner(p_company uuid, p_except uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.company_members m
                  where m.company_id = p_company and m.role = 'owner'
                    and m.active and m.user_id <> p_except);
$function$
;

CREATE OR REPLACE FUNCTION public.company_seat_usage()
 RETURNS TABLE(seats_used integer, seat_limit integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.seats_used(public.auth_company_id()),
         (select c.seat_limit from public.companies c where c.id = public.auth_company_id());
$function$
;

CREATE OR REPLACE FUNCTION public.dashboard_metrics(p_month text, p_owner uuid DEFAULT NULL::uuid)
 RETURNS TABLE(month_label text, leads integer, discovery_appointments integer, presentations integer, estimates_presented integer, plans_presented integer, review_meetings integer, sales_won integer, sales_lost integer, total_clients integer, active_pipeline integer, tasks_due_3 integer, tasks_overdue integer, tasks_overdue_7 integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select (p_month || '-01')::date                              as m_start,
           ((p_month || '-01')::date + interval '1 month')::date as m_end
  ),
  ev as (
    select client_id, to_stage, min(changed_at)::date as d
      from public.client_events group by client_id, to_stage
  ),
  pt as (
    select distinct on (client_id) client_id, presentation_type
      from public.client_events
     where to_stage = 'Presentation Appointment'
     order by client_id, changed_at
  ),
  eff as (
    select c.id,
      coalesce(c.enquiry_date,
        (select min(changed_at)::date from public.client_events x where x.client_id = c.id))  as lead_d,
      coalesce(c.discovery_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Discovery Appointment'))    as disc_d,
      coalesce(c.presentation_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Presentation Appointment')) as pres_d,
      coalesce(c.presentation_type,
        (select presentation_type from pt where pt.client_id = c.id))                              as pres_t,
      coalesce(c.review_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Review / Closing'))         as review_d,
      coalesce(c.won_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Won'))                      as won_d,
      coalesce(c.lost_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Lost'))                     as lost_d
    from public.clients c
    where p_owner is null or c.owner_id = p_owner
  )
  select
    to_char((select m_start from bounds), 'Mon YYYY'),
    (select count(*)::int from eff, bounds where lead_d >= m_start and lead_d < m_end),
    (select count(*)::int from eff, bounds where disc_d >= m_start and disc_d < m_end),
    (select count(*)::int from eff, bounds where pres_d >= m_start and pres_d < m_end),
    (select count(*)::int from eff, bounds where pres_d >= m_start and pres_d < m_end
       and pres_t in ('Estimate','Estimate and Plans')),
    (select count(*)::int from eff, bounds where pres_d >= m_start and pres_d < m_end
       and pres_t in ('Plans','Estimate and Plans')),
    (select count(*)::int from eff, bounds where review_d >= m_start and review_d < m_end),
    (select count(*)::int from eff, bounds where won_d  >= m_start and won_d  < m_end),
    (select count(*)::int from eff, bounds where lost_d >= m_start and lost_d < m_end),
    (select count(*)::int from public.clients where p_owner is null or owner_id = p_owner),
    (select count(*)::int from public.clients
      where (p_owner is null or owner_id = p_owner) and stage not in ('Won','Lost')),
    (select count(*)::int from public.tasks t join public.clients c on c.id = t.client_id
      where not t.done and t.due_date is not null
        and t.due_date >= current_date and t.due_date <= current_date + 3
        and (p_owner is null or c.owner_id = p_owner)),
    (select count(*)::int from public.tasks t join public.clients c on c.id = t.client_id
      where not t.done and t.due_date is not null and t.due_date < current_date
        and (p_owner is null or c.owner_id = p_owner)),
    (select count(*)::int from public.tasks t join public.clients c on c.id = t.client_id
      where not t.done and t.due_date is not null and t.due_date <= current_date - 7
        and (p_owner is null or c.owner_id = p_owner));
$function$
;

CREATE OR REPLACE FUNCTION public.dashboard_month_names(p_month text, p_owner uuid DEFAULT NULL::uuid)
 RETURNS TABLE(category text, client_id uuid, client_name text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select (p_month || '-01')::date                              as m_start,
           ((p_month || '-01')::date + interval '1 month')::date as m_end
  ),
  ev as (
    select client_id, to_stage, min(changed_at)::date as d
      from public.client_events group by client_id, to_stage
  ),
  pt as (
    select distinct on (client_id) client_id, presentation_type
      from public.client_events
     where to_stage = 'Presentation Appointment'
     order by client_id, changed_at
  ),
  eff as (
    select c.id, c.first_name, c.surname,
      coalesce(c.discovery_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Discovery Appointment'))    as disc_d,
      coalesce(c.presentation_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Presentation Appointment')) as pres_d,
      coalesce(c.presentation_type,
        (select presentation_type from pt where pt.client_id = c.id))                              as pres_t,
      coalesce(c.won_date,
        (select d from ev where ev.client_id = c.id and ev.to_stage = 'Won'))                      as won_d
    from public.clients c
    where p_owner is null or c.owner_id = p_owner
  )
  select 'discovery', id, trim(first_name || ' ' || surname)
    from eff, bounds where disc_d >= m_start and disc_d < m_end
  union all
  select 'estimate', id, trim(first_name || ' ' || surname)
    from eff, bounds where pres_d >= m_start and pres_d < m_end
      and pres_t in ('Estimate','Estimate and Plans')
  union all
  select 'won', id, trim(first_name || ' ' || surname)
    from eff, bounds where won_d >= m_start and won_d < m_end
  order by 1, 3;
$function$
;

CREATE OR REPLACE FUNCTION public.dashboard_months()
 RETURNS TABLE(ym text, label text, events integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select to_char(changed_at,'YYYY-MM'), to_char(changed_at,'Mon YYYY'), count(*)::int
  from public.client_events
  group by 1,2
  order by 1 desc;
$function$
;

CREATE OR REPLACE FUNCTION public.guard_current_company()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return new; end if;
  if new.current_company_id is not distinct from old.current_company_id then
    return new;
  end if;
  if new.current_company_id is not null
     and not exists (select 1 from public.company_members m
                      where m.user_id = new.id
                        and m.company_id = new.current_company_id
                        and m.active) then
    raise exception 'You are not a member of that company.' using errcode = '42501';
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.guard_invitation_role()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor public.user_role;
begin
  if auth.uid() is null then return new; end if;
  if public.is_platform_admin() then return new; end if;

  select m.role into v_actor from public.company_members m
   where m.user_id = auth.uid() and m.company_id = new.company_id and m.active;

  if new.role = 'owner' and v_actor is distinct from 'owner' then
    raise exception 'Only an owner can invite another owner.' using errcode = '42501';
  end if;

  if tg_op = 'UPDATE' and old.role is distinct from new.role
     and (new.role = 'owner' or old.role = 'owner')
     and v_actor is distinct from 'owner' then
    raise exception 'Only an owner can change an invitation to or from the owner role.'
      using errcode = '42501';
  end if;
  return new;
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

CREATE OR REPLACE FUNCTION public.invitation_preview(p_token uuid)
 RETURNS TABLE(company_name text, role user_role, email text, valid boolean, reason text, seats_available boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.is_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select m.role in ('owner','admin')
       from public.company_members m
      where m.user_id = auth.uid()
        and m.active
        and m.company_id = public.auth_company_id()),
    false);
$function$
;

CREATE OR REPLACE FUNCTION public.is_platform_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.platform_admins where user_id = auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION public.my_companies()
 RETURNS TABLE(company_id uuid, company_name text, role user_role, is_current boolean, brand_colour text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, m.role,
         (c.id = public.auth_company_id()),
         c.brand_colour
  from public.company_members m
  join public.companies c on c.id = m.company_id
  where m.user_id = auth.uid() and m.active
  order by c.name;
$function$
;

CREATE OR REPLACE FUNCTION public.my_team()
 RETURNS TABLE(user_id uuid, full_name text, email text, role user_role, active boolean, chat_enabled boolean, clients_owned integer, is_me boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.full_name, p.email, m.role, m.active, p.chat_enabled,
         (select count(*)::int from public.clients x
           where x.owner_id = p.id and x.company_id = m.company_id),
         (p.id = auth.uid())
  from public.company_members m
  join public.profiles p on p.id = m.user_id
  where m.company_id = public.auth_company_id()
    and public.auth_company_id() is not null
  order by m.role, p.full_name nulls last, p.email;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_add_membership(p_email text, p_company_id uuid, p_role user_role DEFAULT 'owner'::user_role)
 RETURNS TABLE(user_email text, company_name text, granted_role text, action text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid; v_co text; v_limit int; v_used int; v_existing public.user_role;
begin
  perform public.require_platform_admin();

  select u.id into v_uid from auth.users u where lower(u.email) = lower(trim(p_email));
  if v_uid is null then
    raise exception 'No login exists for %. Create the company with an invitation instead.', p_email
      using errcode='22023';
  end if;

  select name, seat_limit into v_co, v_limit from public.companies where id = p_company_id;
  if v_co is null then raise exception 'No such company.'; end if;

  insert into public.profiles (id, full_name, email, current_company_id)
  select v_uid, nullif(trim(u.raw_user_meta_data->>'full_name'),''), u.email, p_company_id
    from auth.users u where u.id = v_uid
  on conflict (id) do nothing;

  select m.role into v_existing from public.company_members m
   where m.user_id = v_uid and m.company_id = p_company_id;

  if v_existing is not null then
    update public.company_members set role = p_role, active = true
     where user_id = v_uid and company_id = p_company_id;
    perform public.platform_log('membership.update', p_email,
      jsonb_build_object('company', v_co, 'role', p_role));
    return query select p_email, v_co, p_role::text, 'updated'::text;
  end if;

  v_used := public.seats_used(p_company_id);
  if v_used >= v_limit then
    raise exception '% has used all % seats. Add a seat first.', v_co, v_limit using errcode='22023';
  end if;

  insert into public.company_members (user_id, company_id, role) values (v_uid, p_company_id, p_role);
  perform public.platform_log('membership.add', p_email,
    jsonb_build_object('company', v_co, 'role', p_role));
  return query select p_email, v_co, p_role::text, 'added'::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_companies()
 RETURNS TABLE(company_id uuid, company_name text, plan text, seat_limit integer, seats_used integer, owners integer, admins integer, consultants integer, suspended integer, clients integer, open_clients integer, tasks integer, created_at timestamp with time zone, last_activity timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.id, c.name, c.plan, c.seat_limit,
    (select count(*)::int from public.company_members m where m.company_id=c.id and m.active),
    (select count(*)::int from public.company_members m where m.company_id=c.id and m.active and m.role='owner'),
    (select count(*)::int from public.company_members m where m.company_id=c.id and m.active and m.role='admin'),
    (select count(*)::int from public.company_members m where m.company_id=c.id and m.active and m.role='consultant'),
    (select count(*)::int from public.company_members m where m.company_id=c.id and not m.active),
    (select count(*)::int from public.clients x where x.company_id=c.id),
    (select count(*)::int from public.clients x where x.company_id=c.id and x.stage not in ('Won','Lost')),
    (select count(*)::int from public.tasks t where t.company_id=c.id),
    c.created_at,
    greatest(c.updated_at,
      coalesce((select max(x.updated_at) from public.clients x where x.company_id=c.id), c.created_at))
  from public.companies c
  where (select public.is_platform_admin())
  order by c.created_at;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_delete_all_orphans(p_confirm text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
  perform public.require_platform_admin();
  if lower(trim(coalesce(p_confirm,''))) is distinct from 'delete orphans' then
    raise exception 'Type: delete orphans' using errcode = '22023';
  end if;
  with gone as (
    delete from auth.users u
     where not exists (select 1 from public.profiles p where p.id = u.id)
       and u.id <> auth.uid()
    returning 1
  ) select count(*) into v_n from gone;
  perform public.platform_log('orphans.DELETE', 'all', jsonb_build_object('count', v_n));
  return format('%s orphaned login(s) deleted.', v_n);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_delete_company(p_company_id uuid, p_confirm_name text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_people int; v_clients int;
begin
  perform public.require_platform_admin();
  select name into v_name from public.companies where id = p_company_id;
  if v_name is null then raise exception 'No such company.'; end if;
  if lower(trim(coalesce(p_confirm_name,''))) is distinct from lower(trim(v_name)) then
    raise exception 'To confirm permanent deletion, type the company name: %', v_name using errcode='22023';
  end if;

  select count(*) into v_people  from public.company_members where company_id = p_company_id;
  select count(*) into v_clients from public.clients         where company_id = p_company_id;

  perform public.platform_log('company.DELETE', v_name,
    jsonb_build_object('people', v_people, 'clients', v_clients, 'company_id', p_company_id));

  update public.profiles p set current_company_id = (
      select m.company_id from public.company_members m
       where m.user_id = p.id and m.active and m.company_id <> p_company_id
       order by m.created_at limit 1)
   where p.current_company_id = p_company_id;

  delete from public.companies where id = p_company_id;
  return format('Deleted %s: %s membership(s), %s clients. Logins were kept.',
                v_name, v_people, v_clients);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_delete_user(p_user_id uuid, p_confirm_email text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_email text; v_clients int; v_stuck text;
begin
  perform public.require_platform_admin();
  select u.email into v_email from auth.users u where u.id = p_user_id;
  if v_email is null then raise exception 'No such login.'; end if;
  if lower(trim(coalesce(p_confirm_email,''))) is distinct from lower(trim(v_email)) then
    raise exception 'To confirm permanent deletion, type the email address: %', v_email using errcode='22023';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot delete your own login.' using errcode='42501';
  end if;

  select string_agg(c.name, ', ') into v_stuck
    from public.company_members m join public.companies c on c.id = m.company_id
   where m.user_id = p_user_id and m.role='owner' and m.active
     and not exists (select 1 from public.company_members o
                      where o.company_id = m.company_id and o.role='owner'
                        and o.active and o.user_id <> p_user_id);
  if v_stuck is not null then
    raise exception 'They are the only active owner of: %. Promote someone else first, or delete those companies.', v_stuck
      using errcode='42501';
  end if;

  select count(*) into v_clients from public.clients where owner_id = p_user_id;
  perform public.platform_log('user.DELETE', v_email,
    jsonb_build_object('clients_unassigned', v_clients));

  delete from auth.users where id = p_user_id;
  return format('Deleted %s%s.', v_email,
    case when v_clients > 0 then format(' - %s client(s) are now unassigned', v_clients) else '' end);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_log(p_action text, p_target text, p_detail jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.platform_audit (actor_id, actor_email, action, target, detail)
  values (auth.uid(), (select email from public.profiles where id = auth.uid()), p_action, p_target, p_detail);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_orphans()
 RETURNS TABLE(user_id uuid, email text, created_at timestamp with time zone, confirmed boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.id, u.email, u.created_at, (u.email_confirmed_at is not null)
  from auth.users u
  left join public.profiles p on p.id = u.id
  where p.id is null and (select public.is_platform_admin());
$function$
;

CREATE OR REPLACE FUNCTION public.platform_people()
 RETURNS TABLE(user_id uuid, full_name text, email text, role text, active boolean, company_id uuid, company_name text, clients_owned integer, last_sign_in timestamp with time zone, joined timestamp with time zone, is_platform_admin boolean, company_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.full_name, p.email, m.role::text, m.active,
         c.id, c.name,
         (select count(*)::int from public.clients x
           where x.owner_id = p.id and x.company_id = c.id),
         u.last_sign_in_at, m.created_at,
         exists (select 1 from public.platform_admins pa where pa.user_id = p.id),
         (select count(*)::int from public.company_members m2 where m2.user_id = p.id)
  from public.company_members m
  join public.profiles p  on p.id = m.user_id
  join public.companies c on c.id = m.company_id
  join auth.users u       on u.id = p.id
  where (select public.is_platform_admin())
  order by c.name, m.role, p.full_name;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_remove_membership(p_user_id uuid, p_company_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_email text; v_co text; v_role public.user_role; v_owners int; v_left int;
begin
  perform public.require_platform_admin();
  select p.email, c.name, m.role into v_email, v_co, v_role
    from public.company_members m
    join public.profiles p  on p.id = m.user_id
    join public.companies c on c.id = m.company_id
   where m.user_id = p_user_id and m.company_id = p_company_id;
  if v_email is null then raise exception 'No such membership.'; end if;

  if v_role = 'owner' then
    select count(*) into v_owners from public.company_members m
     where m.company_id = p_company_id and m.role='owner' and m.active and m.user_id <> p_user_id;
    if v_owners = 0 then
      raise exception 'That is the last owner of %. Promote someone else first.', v_co using errcode='42501';
    end if;
  end if;

  delete from public.company_members where user_id = p_user_id and company_id = p_company_id;

  select count(*) into v_left from public.company_members where user_id = p_user_id and active;
  update public.profiles p set current_company_id = (
      select m.company_id from public.company_members m
       where m.user_id = p.id and m.active order by m.created_at limit 1)
   where p.id = p_user_id and p.current_company_id = p_company_id;

  perform public.platform_log('membership.remove', v_email, jsonb_build_object('company', v_co));
  return format('%s removed from %s.%s', v_email, v_co,
    case when v_left = 0 then ' They now belong to no company and cannot sign in to anything.' else '' end);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_reset_password(p_user_id uuid, p_new_password text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_email text;
begin
  perform public.require_platform_admin();

  select u.email into v_email from auth.users u where u.id = p_user_id;
  if v_email is null then raise exception 'No such login.'; end if;

  if length(coalesce(p_new_password,'')) < 10 then
    raise exception 'Temporary password must be at least 10 characters.' using errcode = '22023';
  end if;

  update auth.users
     set encrypted_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at         = now()
   where id = p_user_id;

  -- log THAT it happened, never the password itself
  perform public.platform_log('user.password_reset', v_email, '{}'::jsonb);

  return format('Password reset for %s.', v_email);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_set_company_access(p_company_id uuid, p_active boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_n int;
begin
  perform public.require_platform_admin();
  select name into v_name from public.companies where id = p_company_id;
  if v_name is null then raise exception 'No such company.'; end if;
  update public.company_members set active = p_active where company_id = p_company_id;
  get diagnostics v_n = row_count;
  perform public.platform_log(case when p_active then 'company.restore' else 'company.suspend' end,
                              v_name, jsonb_build_object('people_affected', v_n));
  return v_name || ': ' || v_n || ' people ' || case when p_active then 'restored' else 'suspended' end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_set_person_access(p_user_id uuid, p_company_id uuid, p_active boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_email text; v_role public.user_role; v_owners int; v_co text;
begin
  perform public.require_platform_admin();
  select p.email, m.role, c.name into v_email, v_role, v_co
    from public.company_members m
    join public.profiles p  on p.id = m.user_id
    join public.companies c on c.id = m.company_id
   where m.user_id = p_user_id and m.company_id = p_company_id;
  if v_email is null then raise exception 'No such membership.'; end if;

  if not p_active and v_role = 'owner' then
    select count(*) into v_owners from public.company_members m
     where m.company_id = p_company_id and m.role='owner' and m.active and m.user_id <> p_user_id;
    if v_owners = 0 then
      raise exception 'That is the only active owner of %. Promote someone else first, or suspend the whole company.', v_co
        using errcode='42501';
    end if;
  end if;

  update public.company_members set active = p_active
   where user_id = p_user_id and company_id = p_company_id;
  perform public.platform_log(case when p_active then 'person.restore' else 'person.suspend' end,
                              v_email, jsonb_build_object('company', v_co));
  return case when p_active then 'restored' else 'suspended' end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_set_person_role(p_user_id uuid, p_company_id uuid, p_role user_role)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_email text; v_old public.user_role; v_owners int;
begin
  perform public.require_platform_admin();
  select p.email, m.role into v_email, v_old
    from public.company_members m join public.profiles p on p.id = m.user_id
   where m.user_id = p_user_id and m.company_id = p_company_id;
  if v_email is null then raise exception 'No such membership.'; end if;

  if v_old = 'owner' and p_role <> 'owner' then
    select count(*) into v_owners from public.company_members m
     where m.company_id = p_company_id and m.role='owner' and m.active and m.user_id <> p_user_id;
    if v_owners = 0 then raise exception 'That is the last owner of the company.' using errcode='42501'; end if;
  end if;

  update public.company_members set role = p_role
   where user_id = p_user_id and company_id = p_company_id;
  perform public.platform_log('person.role', v_email,
    jsonb_build_object('from', v_old, 'to', p_role, 'company_id', p_company_id));
  return p_role::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.platform_set_seats(p_company_id uuid, p_seats integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_name text; v_used int;
begin
  perform public.require_platform_admin();
  select name into v_name from public.companies where id = p_company_id;
  if v_name is null then raise exception 'No such company.'; end if;
  if p_seats < 1 then raise exception 'Seats must be at least 1.'; end if;
  v_used := public.seats_used(p_company_id);
  if p_seats < v_used then
    raise exception '% already has % active people.', v_name, v_used using errcode='22023';
  end if;
  update public.companies set seat_limit = p_seats where id = p_company_id;
  perform public.platform_log('company.seats', v_name, jsonb_build_object('seats', p_seats));
  return p_seats;
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

CREATE OR REPLACE FUNCTION public.readmit_user(p_email text, p_company text, p_role user_role DEFAULT 'consultant'::user_role)
 RETURNS TABLE(user_email text, company_name text, granted_role text, action text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid;
begin
  select c.id into v_co from public.companies c where lower(c.name) = lower(trim(p_company));
  if v_co is null then raise exception 'No company called "%"', p_company; end if;
  return query select * from public.platform_add_membership(p_email, v_co, p_role);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.record_stage_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    insert into public.client_events (company_id, client_id, from_stage, to_stage,
                                      presentation_type, owner_id, changed_by, changed_at)
    values (new.company_id, new.id, null, new.stage, new.presentation_type,
            new.owner_id, auth.uid(),
            -- date the first event to the enquiry date when we have one,
            -- so an imported or backdated client lands in the right month
            coalesce(new.enquiry_date::timestamptz, new.created_at, now()));
    return new;
  end if;

  if new.stage is distinct from old.stage
     or (new.stage = 'Presentation Appointment'
         and new.presentation_type is distinct from old.presentation_type) then
    insert into public.client_events (company_id, client_id, from_stage, to_stage,
                                      presentation_type, owner_id, changed_by)
    values (new.company_id, new.id, old.stage, new.stage,
            new.presentation_type, new.owner_id, auth.uid());
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.refresh_profile_shadow(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_role public.user_role; v_active boolean;
begin
  select m.company_id, m.role, m.active into v_co, v_role, v_active
    from public.company_members m
   where m.user_id = p_user
   order by (m.company_id = (select p.current_company_id
                               from public.profiles p where p.id = p_user)) desc,
            m.active desc, m.created_at
   limit 1;

  update public.profiles p
     set company_id = v_co, role = v_role, active = coalesce(v_active, false)
   where p.id = p_user
     and (p.company_id is distinct from v_co
       or p.role       is distinct from v_role
       or p.active     is distinct from coalesce(v_active, false));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.remove_member(p_user_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_role public.user_role; v_email text; v_left int;
begin
  v_co := public.auth_company_id();
  if not public.is_manager() then
    raise exception 'Only an owner or admin can remove someone.' using errcode='42501';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot remove yourself.' using errcode='42501';
  end if;

  select m.role, p.email into v_role, v_email
    from public.company_members m join public.profiles p on p.id = m.user_id
   where m.user_id = p_user_id and m.company_id = v_co;
  if v_role is null then
    raise exception 'That person is not in your company.' using errcode='42501';
  end if;
  if v_role = 'owner' and not public.company_has_other_owner(v_co, p_user_id) then
    raise exception 'This is the last owner of the company. Promote someone else first.'
      using errcode='42501';
  end if;

  delete from public.company_members where user_id = p_user_id and company_id = v_co;

  update public.profiles p set current_company_id = (
      select m2.company_id from public.company_members m2
       where m2.user_id = p.id and m2.active order by m2.created_at limit 1)
   where p.id = p_user_id and p.current_company_id = v_co;

  select count(*) into v_left from public.company_members where user_id = p_user_id and active;
  return format('%s removed.%s', coalesce(v_email,'That person'),
    case when v_left = 0 then ' Their login now belongs to no company.' else '' end);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.reports_by_rep(p_month text)
 RETURNS TABLE(rep_id uuid, discovery integer, presentations integer, reviews integer, won integer, won_prev integer, revenue numeric, budgeted integer, clients_total integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select (p_month || '-01')::date                              as c_start,
           ((p_month || '-01')::date + interval '1 month')::date as c_end,
           ((p_month || '-01')::date - interval '1 month')::date as p_start,
           (p_month || '-01')::date                              as p_end
  ),
  ev as (
    select client_id, to_stage, min(changed_at)::date as d
      from public.client_events group by client_id, to_stage
  ),
  eff as (
    select c.id, c.owner_id, c.budget,
      coalesce(c.discovery_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Discovery Appointment'))    as discovery,
      coalesce(c.presentation_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Presentation Appointment')) as presentation,
      coalesce(c.review_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Review / Closing'))         as review,
      coalesce(c.won_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Won'))                      as won
    from public.clients c
  )
  select
    eff.owner_id,
    count(*) filter (where discovery    >= b.c_start and discovery    < b.c_end)::int,
    count(*) filter (where presentation >= b.c_start and presentation < b.c_end)::int,
    count(*) filter (where review       >= b.c_start and review       < b.c_end)::int,
    count(*) filter (where eff.won      >= b.c_start and eff.won      < b.c_end)::int,
    count(*) filter (where eff.won      >= b.p_start and eff.won      < b.p_end)::int,
    coalesce(sum(budget) filter (where eff.won >= b.c_start and eff.won < b.c_end), 0),
    count(*) filter (where eff.won >= b.c_start and eff.won < b.c_end and budget is not null)::int,
    count(*)::int
  from eff cross join bounds b
  group by eff.owner_id;
$function$
;

CREATE OR REPLACE FUNCTION public.reports_kpis(p_month text, p_owner uuid DEFAULT NULL::uuid)
 RETURNS TABLE(month_label text, prev_label text, discovery_cur integer, discovery_prev integer, presentation_cur integer, presentation_prev integer, review_cur integer, review_prev integer, won_cur integer, won_prev integer, revenue_cur numeric, revenue_prev numeric, budgeted_cur integer, budgeted_prev integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with bounds as (
    select (p_month || '-01')::date                              as c_start,
           ((p_month || '-01')::date + interval '1 month')::date as c_end,
           ((p_month || '-01')::date - interval '1 month')::date as p_start,
           (p_month || '-01')::date                              as p_end
  ),
  ev as (
    select client_id, to_stage, min(changed_at)::date as d
      from public.client_events group by client_id, to_stage
  ),
  eff as (
    select c.id, c.budget,
      coalesce(c.discovery_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Discovery Appointment'))    as discovery,
      coalesce(c.presentation_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Presentation Appointment')) as presentation,
      coalesce(c.review_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Review / Closing'))         as review,
      coalesce(c.won_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Won'))                      as won
    from public.clients c
    where p_owner is null or c.owner_id = p_owner
  )
  select
    to_char((select c_start from bounds), 'Mon YYYY'),
    to_char((select p_start from bounds), 'Mon YYYY'),
    (select count(*)::int from eff, bounds where discovery    >= c_start and discovery    < c_end),
    (select count(*)::int from eff, bounds where discovery    >= p_start and discovery    < p_end),
    (select count(*)::int from eff, bounds where presentation >= c_start and presentation < c_end),
    (select count(*)::int from eff, bounds where presentation >= p_start and presentation < p_end),
    (select count(*)::int from eff, bounds where review       >= c_start and review       < c_end),
    (select count(*)::int from eff, bounds where review       >= p_start and review       < p_end),
    (select count(*)::int from eff, bounds where won          >= c_start and won          < c_end),
    (select count(*)::int from eff, bounds where won          >= p_start and won          < p_end),
    (select coalesce(sum(budget),0) from eff, bounds where won >= c_start and won < c_end),
    (select coalesce(sum(budget),0) from eff, bounds where won >= p_start and won < p_end),
    (select count(*)::int from eff, bounds where won >= c_start and won < c_end and budget is not null),
    (select count(*)::int from eff, bounds where won >= p_start and won < p_end and budget is not null);
$function$
;

CREATE OR REPLACE FUNCTION public.require_platform_admin()
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator access required.' using errcode = '42501';
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sales_report_actuals(p_year integer)
 RETURNS TABLE(owner_id uuid, month integer, leads integer, discovery integer, presentation integer, review integer, won integer)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with ev as (
    select client_id, to_stage, min(changed_at)::date as d
      from public.client_events group by client_id, to_stage
  ),
  eff as (
    select c.owner_id,
      coalesce(c.enquiry_date, c.created_at::date) as lead_d,
      coalesce(c.discovery_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Discovery Appointment'))    as disc_d,
      coalesce(c.presentation_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Presentation Appointment')) as pres_d,
      coalesce(c.review_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Review / Closing'))         as rev_d,
      coalesce(c.won_date,
        (select d from ev where ev.client_id=c.id and ev.to_stage='Won'))                      as won_d
    from public.clients c
    where c.company_id = public.auth_company_id()
      and public.can_view_sales_reports()
      and (public.can_manage_sales_reports() or c.owner_id = auth.uid())
  ),
  hits as (
    select owner_id, 'L' k, lead_d d from eff union all
    select owner_id, 'D', disc_d from eff union all
    select owner_id, 'P', pres_d from eff union all
    select owner_id, 'R', rev_d  from eff union all
    select owner_id, 'W', won_d  from eff
  )
  select owner_id, extract(month from d)::int,
         count(*) filter (where k='L')::int, count(*) filter (where k='D')::int,
         count(*) filter (where k='P')::int, count(*) filter (where k='R')::int,
         count(*) filter (where k='W')::int
    from hits
   where d is not null and extract(year from d)::int = p_year
   group by owner_id, extract(month from d)::int;
$function$
;

CREATE OR REPLACE FUNCTION public.sales_reports_access_list()
 RETURNS TABLE(user_id uuid, full_name text, email text, role user_role, active boolean, has_access boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.full_name, p.email, m.role, m.active,
         (m.role = 'owner' or m.sales_reports_access)
    from public.company_members m
    join public.profiles p on p.id = m.user_id
   where m.company_id = public.auth_company_id()
     and public.auth_role() = 'owner'
   order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
            p.full_name nulls last, p.email;
$function$
;

CREATE OR REPLACE FUNCTION public.seats_used(p_company uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select count(*)::int from public.company_members m
   where m.company_id = p_company and m.active;
$function$
;

CREATE OR REPLACE FUNCTION public.set_member_access(p_user_id uuid, p_active boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_used int; v_limit int; v_role public.user_role; v_act boolean;
begin
  v_co := public.auth_company_id();
  if not public.is_manager() then
    raise exception 'Only an owner or admin can change someone''s access.' using errcode='42501';
  end if;
  if p_user_id = auth.uid() and not p_active then
    raise exception 'You cannot remove your own access.' using errcode='42501';
  end if;

  select m.role, m.active into v_role, v_act from public.company_members m
   where m.user_id = p_user_id and m.company_id = v_co;
  if v_role is null then
    raise exception 'That person is not in your company.' using errcode='42501';
  end if;

  if not p_active and v_role = 'owner' and v_act
     and not public.company_has_other_owner(v_co, p_user_id) then
    raise exception 'This is the last owner of the company. Promote someone else first.'
      using errcode='42501';
  end if;

  if p_active then
    v_used := public.seats_used(v_co);
    select seat_limit into v_limit from public.companies where id = v_co;
    if v_used >= v_limit then
      raise exception 'All % seats are in use. Add a seat first.', v_limit using errcode='22023';
    end if;
  end if;

  update public.company_members set active = p_active
   where user_id = p_user_id and company_id = v_co;
  return case when p_active then 'restored' else 'deactivated' end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_member_chat_access(p_user_id uuid, p_enabled boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_role public.user_role;
begin
  v_co := public.auth_company_id();
  if not public.is_manager() then
    raise exception 'Only an owner or admin can change someone''s chat access.' using errcode='42501';
  end if;

  select m.role into v_role from public.company_members m
   where m.user_id = p_user_id and m.company_id = v_co;
  if v_role is null then
    raise exception 'That person is not in your company.' using errcode='42501';
  end if;

  update public.profiles set chat_enabled = p_enabled where id = p_user_id;
  return case when p_enabled then 'enabled' else 'disabled' end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_member_role(p_user_id uuid, p_role user_role)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_actor public.user_role; v_old public.user_role; v_act boolean;
begin
  v_co := public.auth_company_id();
  select m.role into v_actor from public.company_members m
   where m.user_id = auth.uid() and m.company_id = v_co and m.active;
  if v_actor is null or v_actor not in ('owner','admin') then
    raise exception 'Only an owner or admin can change a role.' using errcode='42501';
  end if;

  select m.role, m.active into v_old, v_act from public.company_members m
   where m.user_id = p_user_id and m.company_id = v_co;
  if v_old is null then
    raise exception 'That person is not in your company.' using errcode='42501';
  end if;

  if v_actor = 'admin' and (p_role = 'owner' or v_old = 'owner') then
    raise exception 'Only an owner can grant or remove the owner role.' using errcode='42501';
  end if;

  -- last-owner protection, applied to the action and never waived
  if v_old = 'owner' and v_act and p_role <> 'owner'
     and not public.company_has_other_owner(v_co, p_user_id) then
    raise exception 'This is the last owner of the company. Promote someone else first.'
      using errcode='42501';
  end if;

  update public.company_members set role = p_role
   where user_id = p_user_id and company_id = v_co;
  return p_role::text;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_sales_reports_access(p_user_id uuid, p_enabled boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_co uuid; v_role public.user_role;
begin
  v_co := public.auth_company_id();
  if public.auth_role() is distinct from 'owner' then
    raise exception 'Only an owner can change who sees Sales Reports.' using errcode = '42501';
  end if;
  select m.role into v_role from public.company_members m
   where m.user_id = p_user_id and m.company_id = v_co;
  if v_role is null then
    raise exception 'That person is not in your company.' using errcode = '42501';
  end if;
  if v_role = 'owner' then
    raise exception 'Owners always see Sales Reports.' using errcode = '22023';
  end if;
  update public.company_members set sales_reports_access = p_enabled
   where user_id = p_user_id and company_id = v_co;
  return case when p_enabled then 'enabled' else 'disabled' end;
end;
$function$
;

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

CREATE OR REPLACE FUNCTION public.shares_current_company(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.company_members m
     where m.user_id = p_user
       and m.company_id = public.auth_company_id());
$function$
;

CREATE OR REPLACE FUNCTION public.stamp_platform_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  NEW.sender_id := auth.uid();
  SELECT coalesce(nullif(p.full_name,''), split_part(p.email,'@',1), 'Someone'), p.company_id
    INTO NEW.sender_name, NEW.company_id
    FROM public.profiles p WHERE p.id = auth.uid();
  NEW.company_name := '';
  IF NEW.company_id IS NOT NULL THEN
    SELECT c.name INTO NEW.company_name FROM public.companies c WHERE c.id = NEW.company_id;
  END IF;
  NEW.created_at := now();
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.switch_company(p_company_id uuid)
 RETURNS TABLE(company_id uuid, company_name text, role user_role)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_name text;
begin
  select m.role into v_role from public.company_members m
   where m.user_id = auth.uid() and m.company_id = p_company_id and m.active;
  if v_role is null then
    raise exception 'You are not an active member of that company.' using errcode='42501';
  end if;
  update public.profiles set current_company_id = p_company_id where id = auth.uid();
  select name into v_name from public.companies where id = p_company_id;
  return query select p_company_id, v_name, v_role;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_shadow_from_membership()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_profile_shadow(old.user_id);
    return old;
  end if;
  perform public.refresh_profile_shadow(new.user_id);
  if tg_op = 'UPDATE' and old.user_id <> new.user_id then
    perform public.refresh_profile_shadow(old.user_id);
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.trg_shadow_from_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.refresh_profile_shadow(new.id);
  return null;
end;
$function$
;

CREATE TRIGGER clients_stage_history AFTER INSERT OR UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION record_stage_event();

CREATE TRIGGER clients_touch BEFORE UPDATE ON public.clients FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER companies_touch BEFORE UPDATE ON public.companies FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER company_members_shadow AFTER INSERT OR DELETE OR UPDATE ON public.company_members FOR EACH ROW EXECUTE FUNCTION trg_shadow_from_membership();

CREATE TRIGGER dwellings_touch BEFORE UPDATE ON public.dwellings FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER invitations_guard BEFORE INSERT OR UPDATE ON public.invitations FOR EACH ROW EXECUTE FUNCTION guard_invitation_role();

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_user();

CREATE TRIGGER profiles_current_company_guard BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION guard_current_company();

CREATE TRIGGER profiles_shadow AFTER INSERT OR UPDATE OF current_company_id ON public.profiles FOR EACH ROW EXECUTE FUNCTION trg_shadow_from_profile();

CREATE TRIGGER tasks_touch BEFORE UPDATE ON public.tasks FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_stamp_platform_message BEFORE INSERT ON public.platform_messages FOR EACH ROW EXECUTE FUNCTION stamp_platform_message();

create policy chat_conversations_select on public.chat_conversations as PERMISSIVE for SELECT to authenticated using ((((kind = 'dm'::text) AND ((auth.uid() = user_a) OR (auth.uid() = user_b))) OR ((kind = 'team'::text) AND ((auth_company_id() = company_a) OR (auth_company_id() = company_b)))));

create policy chat_reads_insert on public.chat_reads as PERMISSIVE for INSERT to authenticated with check ((user_id = auth.uid()));

create policy chat_reads_select on public.chat_reads as PERMISSIVE for SELECT to authenticated using ((user_id = auth.uid()));

create policy chat_reads_update on public.chat_reads as PERMISSIVE for UPDATE to authenticated using ((user_id = auth.uid())) with check ((user_id = auth.uid()));

create policy cldocs_insert on public.client_documents as PERMISSIVE for INSERT to public with check (((company_id = auth_company_id()) AND (uploaded_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM clients c
  WHERE (c.id = client_documents.client_id)))));

create policy cldocs_select on public.client_documents as PERMISSIVE for SELECT to public using (((company_id = auth_company_id()) AND (EXISTS ( SELECT 1
   FROM clients c
  WHERE (c.id = client_documents.client_id)))));

create policy cldocs_update on public.client_documents as PERMISSIVE for UPDATE to public using (((company_id = auth_company_id()) AND (EXISTS ( SELECT 1
   FROM clients c
  WHERE (c.id = client_documents.client_id))))) with check ((company_id = auth_company_id()));

create policy client_events_select on public.client_events as PERMISSIVE for SELECT to authenticated using (((company_id = auth_company_id()) AND can_reach_client(client_id, company_id)));

create policy clients_delete on public.clients as PERMISSIVE for DELETE to authenticated using (((company_id = auth_company_id()) AND (is_manager() OR (owner_id = auth.uid()))));

create policy clients_insert on public.clients as PERMISSIVE for INSERT to authenticated with check (((company_id = auth_company_id()) AND (is_manager() OR (owner_id = auth.uid()))));

create policy clients_select on public.clients as PERMISSIVE for SELECT to authenticated using (((company_id = auth_company_id()) AND (is_manager() OR (owner_id = auth.uid()))));

create policy clients_update on public.clients as PERMISSIVE for UPDATE to authenticated using (((company_id = auth_company_id()) AND (is_manager() OR (owner_id = auth.uid())))) with check (((company_id = auth_company_id()) AND (is_manager() OR (owner_id = auth.uid()))));

create policy companies_select on public.companies as PERMISSIVE for SELECT to authenticated using ((id = auth_company_id()));

create policy companies_update on public.companies as PERMISSIVE for UPDATE to authenticated using (((id = auth_company_id()) AND is_manager())) with check (((id = auth_company_id()) AND is_manager()));

create policy company_members_select on public.company_members as PERMISSIVE for SELECT to public using ((company_id = auth_company_id()));

create policy dwellings_all on public.dwellings as PERMISSIVE for ALL to authenticated using (((company_id = auth_company_id()) AND can_reach_client(client_id, company_id))) with check (((company_id = auth_company_id()) AND can_reach_client(client_id, company_id)));

create policy invitations_delete on public.invitations as PERMISSIVE for DELETE to authenticated using (((company_id = auth_company_id()) AND is_manager()));

create policy invitations_insert on public.invitations as PERMISSIVE for INSERT to authenticated with check (((company_id = auth_company_id()) AND is_manager()));

create policy invitations_select on public.invitations as PERMISSIVE for SELECT to authenticated using (((company_id = auth_company_id()) AND is_manager()));

create policy invitations_update on public.invitations as PERMISSIVE for UPDATE to authenticated using (((company_id = auth_company_id()) AND is_manager())) with check (((company_id = auth_company_id()) AND is_manager()));

create policy profiles_select on public.profiles as PERMISSIVE for SELECT to public using (((id = auth.uid()) OR shares_current_company(id)));

create policy profiles_update on public.profiles as PERMISSIVE for UPDATE to public using ((id = auth.uid())) with check ((id = auth.uid()));

create policy sales_kpi_rates_delete on public.sales_kpi_rates as PERMISSIVE for DELETE to authenticated using (((company_id = auth_company_id()) AND can_manage_sales_reports()));

create policy sales_kpi_rates_insert on public.sales_kpi_rates as PERMISSIVE for INSERT to authenticated with check (((company_id = auth_company_id()) AND can_manage_sales_reports() AND shares_current_company(owner_id)));

create policy sales_kpi_rates_select on public.sales_kpi_rates as PERMISSIVE for SELECT to authenticated using (((company_id = auth_company_id()) AND (can_manage_sales_reports() OR (can_view_sales_reports() AND (owner_id = auth.uid())))));

create policy sales_kpi_rates_update on public.sales_kpi_rates as PERMISSIVE for UPDATE to authenticated using (((company_id = auth_company_id()) AND can_manage_sales_reports())) with check (((company_id = auth_company_id()) AND can_manage_sales_reports() AND shares_current_company(owner_id)));

create policy sales_kpis_delete on public.sales_kpis as PERMISSIVE for DELETE to authenticated using (((company_id = auth_company_id()) AND can_manage_sales_reports()));

create policy sales_kpis_insert on public.sales_kpis as PERMISSIVE for INSERT to authenticated with check (((company_id = auth_company_id()) AND can_manage_sales_reports() AND shares_current_company(owner_id)));

create policy sales_kpis_select on public.sales_kpis as PERMISSIVE for SELECT to authenticated using (((company_id = auth_company_id()) AND (can_manage_sales_reports() OR (can_view_sales_reports() AND (owner_id = auth.uid())))));

create policy sales_kpis_update on public.sales_kpis as PERMISSIVE for UPDATE to authenticated using (((company_id = auth_company_id()) AND can_manage_sales_reports())) with check (((company_id = auth_company_id()) AND can_manage_sales_reports() AND shares_current_company(owner_id)));

create policy tasks_all on public.tasks as PERMISSIVE for ALL to authenticated using (((company_id = auth_company_id()) AND can_reach_client(client_id, company_id))) with check (((company_id = auth_company_id()) AND can_reach_client(client_id, company_id)));

-- Supabase default privileges grant EXECUTE on public functions to anon, authenticated and
-- service_role; the revokes below are the project's hardening on top of that.
grant execute on all functions in schema public to anon, authenticated, service_role;

revoke execute on function public.auth_company_id() from public;

revoke execute on function public.auth_company_id() from anon;

revoke execute on function public.auth_role() from public;

revoke execute on function public.auth_role() from anon;

revoke execute on function public.can_manage_sales_reports() from public;

revoke execute on function public.can_manage_sales_reports() from anon;

revoke execute on function public.can_reach_client(p_client_id uuid, p_company_id uuid) from anon;

revoke execute on function public.can_reach_client(p_client_id uuid, p_company_id uuid) from public;

revoke execute on function public.can_see_conversation(p_conversation_id uuid) from anon;

revoke execute on function public.can_see_conversation(p_conversation_id uuid) from public;

revoke execute on function public.can_see_conversation(p_conversation_id uuid) from authenticated;

revoke execute on function public.can_view_sales_reports() from anon;

revoke execute on function public.can_view_sales_reports() from public;

revoke execute on function public.chat_mark_read(p_conversation_id uuid) from public;

revoke execute on function public.chat_mark_read(p_conversation_id uuid) from anon;

revoke execute on function public.chat_mark_read(p_conversation_id uuid) from authenticated;

revoke execute on function public.chat_my_conversations() from authenticated;

revoke execute on function public.chat_my_conversations() from public;

revoke execute on function public.chat_my_conversations() from anon;

revoke execute on function public.chat_people_directory() from anon;

revoke execute on function public.chat_people_directory() from authenticated;

revoke execute on function public.chat_people_directory() from public;

revoke execute on function public.chat_start_dm(p_other_user uuid) from public;

revoke execute on function public.chat_start_dm(p_other_user uuid) from authenticated;

revoke execute on function public.chat_start_dm(p_other_user uuid) from anon;

revoke execute on function public.chat_start_team(p_company_id uuid) from anon;

revoke execute on function public.chat_start_team(p_company_id uuid) from authenticated;

revoke execute on function public.chat_start_team(p_company_id uuid) from public;

revoke execute on function public.chat_teams_directory() from authenticated;

revoke execute on function public.chat_teams_directory() from anon;

revoke execute on function public.chat_teams_directory() from public;

revoke execute on function public.chat_unread_summary() from anon;

revoke execute on function public.chat_unread_summary() from public;

revoke execute on function public.chat_unread_summary() from authenticated;

revoke execute on function public.company_has_other_owner(p_company uuid, p_except uuid) from public;

revoke execute on function public.company_has_other_owner(p_company uuid, p_except uuid) from anon;

revoke execute on function public.company_seat_usage() from anon;

revoke execute on function public.company_seat_usage() from public;

revoke execute on function public.dashboard_metrics(p_month text, p_owner uuid) from public;

revoke execute on function public.dashboard_metrics(p_month text, p_owner uuid) from anon;

revoke execute on function public.dashboard_months() from anon;

revoke execute on function public.dashboard_months() from public;

revoke execute on function public.guard_current_company() from anon;

revoke execute on function public.guard_current_company() from public;

revoke execute on function public.guard_invitation_role() from anon;

revoke execute on function public.guard_invitation_role() from public;

revoke execute on function public.handle_new_user() from anon;

revoke execute on function public.handle_new_user() from authenticated;

revoke execute on function public.handle_new_user() from public;

revoke execute on function public.is_manager() from anon;

revoke execute on function public.is_manager() from public;

revoke execute on function public.is_platform_admin() from anon;

revoke execute on function public.is_platform_admin() from public;

revoke execute on function public.my_companies() from public;

revoke execute on function public.my_companies() from anon;

revoke execute on function public.my_team() from public;

revoke execute on function public.my_team() from anon;

revoke execute on function public.platform_add_membership(p_email text, p_company_id uuid, p_role user_role) from public;

revoke execute on function public.platform_add_membership(p_email text, p_company_id uuid, p_role user_role) from anon;

revoke execute on function public.platform_companies() from public;

revoke execute on function public.platform_companies() from anon;

revoke execute on function public.platform_delete_all_orphans(p_confirm text) from anon;

revoke execute on function public.platform_delete_all_orphans(p_confirm text) from public;

revoke execute on function public.platform_delete_company(p_company_id uuid, p_confirm_name text) from anon;

revoke execute on function public.platform_delete_company(p_company_id uuid, p_confirm_name text) from public;

revoke execute on function public.platform_delete_user(p_user_id uuid, p_confirm_email text) from anon;

revoke execute on function public.platform_delete_user(p_user_id uuid, p_confirm_email text) from public;

revoke execute on function public.platform_log(p_action text, p_target text, p_detail jsonb) from anon;

revoke execute on function public.platform_log(p_action text, p_target text, p_detail jsonb) from public;

revoke execute on function public.platform_log(p_action text, p_target text, p_detail jsonb) from authenticated;

revoke execute on function public.platform_orphans() from anon;

revoke execute on function public.platform_orphans() from public;

revoke execute on function public.platform_people() from public;

revoke execute on function public.platform_people() from anon;

revoke execute on function public.platform_remove_membership(p_user_id uuid, p_company_id uuid) from anon;

revoke execute on function public.platform_remove_membership(p_user_id uuid, p_company_id uuid) from public;

revoke execute on function public.platform_reset_password(p_user_id uuid, p_new_password text) from public;

revoke execute on function public.platform_reset_password(p_user_id uuid, p_new_password text) from anon;

revoke execute on function public.platform_set_company_access(p_company_id uuid, p_active boolean) from public;

revoke execute on function public.platform_set_company_access(p_company_id uuid, p_active boolean) from anon;

revoke execute on function public.platform_set_person_access(p_user_id uuid, p_company_id uuid, p_active boolean) from public;

revoke execute on function public.platform_set_person_access(p_user_id uuid, p_company_id uuid, p_active boolean) from anon;

revoke execute on function public.platform_set_person_role(p_user_id uuid, p_company_id uuid, p_role user_role) from public;

revoke execute on function public.platform_set_person_role(p_user_id uuid, p_company_id uuid, p_role user_role) from anon;

revoke execute on function public.platform_set_seats(p_company_id uuid, p_seats integer) from public;

revoke execute on function public.platform_set_seats(p_company_id uuid, p_seats integer) from anon;

revoke execute on function public.provision_company(p_company text, p_email text, p_seats integer, p_role user_role, p_plan text) from anon;

revoke execute on function public.provision_company(p_company text, p_email text, p_seats integer, p_role user_role, p_plan text) from public;

revoke execute on function public.readmit_user(p_email text, p_company text, p_role user_role) from public;

revoke execute on function public.readmit_user(p_email text, p_company text, p_role user_role) from anon;

revoke execute on function public.record_stage_event() from public;

revoke execute on function public.record_stage_event() from anon;

revoke execute on function public.refresh_profile_shadow(p_user uuid) from anon;

revoke execute on function public.refresh_profile_shadow(p_user uuid) from public;

revoke execute on function public.remove_member(p_user_id uuid) from anon;

revoke execute on function public.remove_member(p_user_id uuid) from public;

revoke execute on function public.reports_by_rep(p_month text) from anon;

revoke execute on function public.reports_by_rep(p_month text) from public;

revoke execute on function public.reports_kpis(p_month text, p_owner uuid) from public;

revoke execute on function public.reports_kpis(p_month text, p_owner uuid) from anon;

revoke execute on function public.require_platform_admin() from anon;

revoke execute on function public.require_platform_admin() from authenticated;

revoke execute on function public.require_platform_admin() from public;

revoke execute on function public.sales_report_actuals(p_year integer) from anon;

revoke execute on function public.sales_report_actuals(p_year integer) from public;

revoke execute on function public.sales_reports_access_list() from anon;

revoke execute on function public.sales_reports_access_list() from public;

revoke execute on function public.seats_used(p_company uuid) from anon;

revoke execute on function public.seats_used(p_company uuid) from public;

revoke execute on function public.set_member_access(p_user_id uuid, p_active boolean) from public;

revoke execute on function public.set_member_access(p_user_id uuid, p_active boolean) from anon;

revoke execute on function public.set_member_chat_access(p_user_id uuid, p_enabled boolean) from anon;

revoke execute on function public.set_member_chat_access(p_user_id uuid, p_enabled boolean) from authenticated;

revoke execute on function public.set_member_chat_access(p_user_id uuid, p_enabled boolean) from public;

revoke execute on function public.set_member_role(p_user_id uuid, p_role user_role) from anon;

revoke execute on function public.set_member_role(p_user_id uuid, p_role user_role) from public;

revoke execute on function public.set_sales_reports_access(p_user_id uuid, p_enabled boolean) from anon;

revoke execute on function public.set_sales_reports_access(p_user_id uuid, p_enabled boolean) from public;

revoke execute on function public.set_seat_limit(p_limit integer) from anon;

revoke execute on function public.set_seat_limit(p_limit integer) from public;

revoke execute on function public.shares_current_company(p_user uuid) from public;

revoke execute on function public.shares_current_company(p_user uuid) from anon;

revoke execute on function public.stamp_platform_message() from public;

revoke execute on function public.stamp_platform_message() from anon;

revoke execute on function public.stamp_platform_message() from authenticated;

revoke execute on function public.switch_company(p_company_id uuid) from anon;

revoke execute on function public.switch_company(p_company_id uuid) from public;

revoke execute on function public.touch_updated_at() from public;

revoke execute on function public.touch_updated_at() from anon;

grant UPDATE, SELECT, INSERT on public.client_documents to authenticated;

grant INSERT, DELETE, UPDATE, SELECT, TRIGGER, REFERENCES, TRUNCATE on public.client_events to anon;

grant DELETE, TRUNCATE, REFERENCES, TRIGGER, INSERT, SELECT, UPDATE on public.client_events to authenticated;

grant TRUNCATE, UPDATE, SELECT, INSERT, TRIGGER, REFERENCES, DELETE on public.clients to anon;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.clients to authenticated;

grant INSERT, TRUNCATE, REFERENCES, TRIGGER, SELECT, UPDATE, DELETE on public.companies to anon;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.companies to authenticated;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.company_members to anon;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.company_members to authenticated;

grant DELETE, INSERT, SELECT, UPDATE, TRUNCATE, REFERENCES, TRIGGER on public.dwellings to anon;

grant INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, SELECT on public.dwellings to authenticated;

grant DELETE, UPDATE, SELECT, INSERT, TRIGGER, REFERENCES, TRUNCATE on public.invitations to anon;

grant INSERT, REFERENCES, TRUNCATE, DELETE, TRIGGER, UPDATE, SELECT on public.invitations to authenticated;

grant REFERENCES, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, TRIGGER on public.platform_admins to anon;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.platform_admins to authenticated;

grant TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT, INSERT on public.platform_audit to anon;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.platform_audit to authenticated;

grant DELETE, TRUNCATE, REFERENCES, TRIGGER, INSERT, SELECT, UPDATE on public.profiles to anon;

grant UPDATE, TRIGGER, REFERENCES, TRUNCATE, INSERT, SELECT, DELETE on public.profiles to authenticated;

grant TRIGGER, INSERT, SELECT, UPDATE, DELETE, TRUNCATE, REFERENCES on public.sales_kpi_rates to authenticated;

grant INSERT, TRIGGER, REFERENCES, TRUNCATE, DELETE, UPDATE, SELECT on public.sales_kpis to authenticated;

grant DELETE, UPDATE, SELECT, INSERT, TRIGGER, REFERENCES, TRUNCATE on public.tasks to anon;

grant TRUNCATE, UPDATE, SELECT, INSERT, TRIGGER, REFERENCES, DELETE on public.tasks to authenticated;
