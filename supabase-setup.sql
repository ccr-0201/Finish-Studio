-- Chay toan bo file nay trong Supabase: SQL Editor > New query > dan vao > Run.

create table public.profiles(
  id uuid primary key references auth.users on delete cascade,
  uid text unique not null,
  display_name text,
  settings jsonb default '{}'::jsonb);
create table public.models(
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null, fmt text, size bigint, path text not null,
  created_at timestamptz default now());
create table public.shares(
  model_id uuid references public.models on delete cascade,
  user_id uuid references auth.users on delete cascade,
  can_edit boolean default true,
  primary key(model_id,user_id));
create table public.scene_states(
  model_id uuid primary key references public.models on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_by uuid, updated_at timestamptz default now());
create table public.maps(
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  name text, path text not null, created_at timestamptz default now());

alter table public.profiles enable row level security;
alter table public.models enable row level security;
alter table public.shares enable row level security;
alter table public.scene_states enable row level security;
alter table public.maps enable row level security;

-- ham phu (security definer) de tranh vong lap chinh sach
create or replace function public.is_owner(mid uuid) returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from public.models m where m.id=mid and m.owner=auth.uid()) $$;
create or replace function public.can_see(mid uuid) returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from public.models m where m.id=mid and (m.owner=auth.uid() or exists(select 1 from public.shares s where s.model_id=m.id and s.user_id=auth.uid()))) $$;
create or replace function public.can_edit(mid uuid) returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from public.models m where m.id=mid and (m.owner=auth.uid() or exists(select 1 from public.shares s where s.model_id=m.id and s.user_id=auth.uid() and s.can_edit))) $$;

create policy p_sel on public.profiles for select to authenticated using (true);
create policy p_ins on public.profiles for insert to authenticated with check (id=auth.uid());
create policy p_upd on public.profiles for update to authenticated using (id=auth.uid());

create policy m_sel on public.models for select to authenticated using (public.can_see(id));
create policy m_ins on public.models for insert to authenticated with check (owner=auth.uid());
create policy m_del on public.models for delete to authenticated using (owner=auth.uid());

create policy s_sel on public.shares for select to authenticated using (user_id=auth.uid() or public.is_owner(model_id));
create policy s_ins on public.shares for insert to authenticated with check (public.is_owner(model_id));
create policy s_upd on public.shares for update to authenticated using (public.is_owner(model_id));
create policy s_del on public.shares for delete to authenticated using (public.is_owner(model_id));

create policy st_sel on public.scene_states for select to authenticated using (public.can_see(model_id));
create policy st_ins on public.scene_states for insert to authenticated with check (public.can_edit(model_id));
create policy st_upd on public.scene_states for update to authenticated using (public.can_edit(model_id));

create policy mp_sel on public.maps for select to authenticated using (true);
create policy mp_ins on public.maps for insert to authenticated with check (owner=auth.uid());
create policy mp_del on public.maps for delete to authenticated using (owner=auth.uid());

-- kho luu tru (rieng tu)
insert into storage.buckets(id,name,public) values ('models','models',false),('maps','maps',false) on conflict do nothing;
create policy so_models_ins on storage.objects for insert to authenticated with check (bucket_id='models' and (storage.foldername(name))[1]=auth.uid()::text);
create policy so_models_sel on storage.objects for select to authenticated using (bucket_id='models' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.models m where m.path=name and public.can_see(m.id))));
create policy so_models_del on storage.objects for delete to authenticated using (bucket_id='models' and (storage.foldername(name))[1]=auth.uid()::text);
create policy so_maps_ins on storage.objects for insert to authenticated with check (bucket_id='maps' and (storage.foldername(name))[1]=auth.uid()::text);
create policy so_maps_sel on storage.objects for select to authenticated using (bucket_id='maps');
create policy so_maps_del on storage.objects for delete to authenticated using (bucket_id='maps' and (storage.foldername(name))[1]=auth.uid()::text);

-- cap nhat truc tiep giua nhieu nguoi cung xem
alter publication supabase_realtime add table public.scene_states;
