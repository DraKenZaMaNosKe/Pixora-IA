-- AURA wellness audio catalog
-- Project: vzuwvsmlyigjtsearxym

-- 1. Public bucket
insert into storage.buckets (id, name, public)
values ('aura-audio', 'aura-audio', true)
on conflict (id) do nothing;

-- Public read on bucket objects
do $$ begin
  create policy "aura-audio public read"
    on storage.objects for select
    using ( bucket_id = 'aura-audio' );
exception when duplicate_object then null; end $$;

-- 2. Catalog table
create table if not exists public.aura_tracks (
  id              text primary key,
  category        text not null check (category in ('frequency','nature')),
  hz              integer,
  chakra          text,
  color_hex       text,
  icon            text,
  name_en         text not null,
  name_es         text not null,
  desc_en         text not null,
  desc_es         text not null,
  duration_sec    integer not null,
  file_path       text not null,
  audio_url       text not null,
  license         text not null default 'CC0',
  freesound_id    bigint,
  freesound_user  text,
  sort_order      integer not null default 0,
  created_at      timestamptz not null default now()
);

create index if not exists aura_tracks_category_idx
  on public.aura_tracks (category, sort_order);

alter table public.aura_tracks enable row level security;

do $$ begin
  create policy "aura_tracks public read"
    on public.aura_tracks for select
    using ( true );
exception when duplicate_object then null; end $$;
