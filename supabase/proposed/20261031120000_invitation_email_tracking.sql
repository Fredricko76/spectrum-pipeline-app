-- PROPOSED - not applied. Optional: lets the team-invite edge function rate-limit invite emails
-- and lets the Team screen show when an invite was last emailed.
-- The function and the app both work WITHOUT this migration (they check for the columns).
-- Additive only: two nullable/defaulted columns, no data changes, no policy changes.
-- Undo: 20261031120000_invitation_email_tracking_undo.sql
alter table public.invitations
  add column if not exists last_emailed_at timestamptz,
  add column if not exists email_count integer not null default 0;

comment on column public.invitations.last_emailed_at is
  'When the team-invite edge function last emailed this invite (null = never emailed, link only).';
comment on column public.invitations.email_count is
  'How many times the team-invite edge function has emailed this invite (capped in the function).';
