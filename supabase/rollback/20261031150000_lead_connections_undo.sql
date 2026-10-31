-- Undo for 20261031150000_lead_connections.sql. Drops the functions only.
-- Any lead_sources rows (keys) created through the screen are kept and keep working
-- with the website-enquiry function. Delete them separately only if you mean to.
drop function if exists public.lead_source_update(uuid, uuid, boolean);
drop function if exists public.lead_source_regenerate(uuid);
drop function if exists public.lead_source_create(text, text);
drop function if exists public.my_lead_sources();
drop function if exists public.lead_source_new_key();
