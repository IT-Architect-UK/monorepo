-- Social content pool (Darren, 2026-08-31): Facebook posts are drafted into
-- this table, approved on the dashboard's Social tab, and published by the
-- collector at the agreed slots (09:00 / 13:00 / 20:00 UTC). Every row keeps
-- its outcome (post id or error), so the table doubles as the posting log.
--
-- Staff may change status/body from the browser (approve, retire, edit);
-- the collector's service role owns the posting outcome fields.

create table if not exists public.social_posts (
  id            text primary key,                 -- fb-YYYYMM-NNN
  platform      text not null default 'facebook',
  topic         text,
  body          text not null,
  status        text not null default 'draft',    -- draft | approved | posted | failed | retired
  created_at    timestamptz not null default now(),
  approved_by   text,
  approved_at   timestamptz,
  posted_at     timestamptz,
  post_id       text,
  attempts      integer not null default 0,
  error         text,
  updated_by    text,
  updated_at    timestamptz not null default now()
);

create index if not exists social_posts_status_idx on public.social_posts (status, created_at);

comment on table public.social_posts is
  'Facebook content pool + posting log. Drafts are seeded from data/social/posts.json; '
  'staff approve on the dashboard; the collector posts from the approved pool.';

alter table public.social_posts enable row level security;

drop policy if exists staff_read on public.social_posts;
create policy staff_read on public.social_posts for select
  to authenticated using (public.is_staff());
drop policy if exists staff_update on public.social_posts;
create policy staff_update on public.social_posts for update
  to authenticated using (public.is_staff()) with check (public.is_staff());

grant select, update on public.social_posts to authenticated;
grant select, insert, update, delete on public.social_posts to service_role;

drop trigger if exists social_posts_touch on public.social_posts;
create trigger social_posts_touch before update on public.social_posts
  for each row execute function public.touch_updated_at();

notify pgrst, 'reload schema';
