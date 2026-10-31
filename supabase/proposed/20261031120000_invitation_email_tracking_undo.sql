-- Undo for 20261031120000_invitation_email_tracking.sql (drops only the two tracking columns).
alter table public.invitations
  drop column if exists email_count,
  drop column if exists last_emailed_at;
