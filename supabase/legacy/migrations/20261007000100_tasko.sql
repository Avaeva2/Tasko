-- Tasko v2: personal/team projects. All client access requires an Auth session.
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '' check (char_length(name) <= 120),
  role text not null default '' check (char_length(role) <= 120),
  updated_at timestamptz not null default now()
);
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  name text not null check (char_length(trim(name)) between 1 and 120),
  created_at timestamptz not null default now()
);
create table public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  primary key (team_id, user_id)
);
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  team_id uuid references public.teams(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 120),
  key text not null check (key ~ '^[A-Z][A-Z0-9]{1,9}$'),
  description text not null default '' check (char_length(description) <= 10000),
  due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, key)
);
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) default auth.uid(),
  title text not null check (char_length(trim(title)) between 1 and 200),
  description text not null default '' check (char_length(description) <= 10000),
  status text not null default 'todo' check (status in ('todo','in_progress','review','blocked','done')),
  priority text not null default 'medium' check (priority in ('low','medium','high','urgent')),
  due_date date,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'done') = (completed_at is not null))
);
create index tasks_project_status on public.tasks(project_id, status);
create index tasks_due_date on public.tasks(due_date) where status <> 'done';
create index team_members_user on public.team_members(user_id, team_id);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  created_by uuid not null references auth.users(id) default auth.uid(),
  title text not null check (char_length(trim(title)) between 1 and 120),
  period_start date,
  period_end date,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (period_start is null or period_end is null or period_end >= period_start)
);

create function private.owns_team(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.teams where id = target and owner_id = (select auth.uid()));
$$;
create function private.in_team(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.teams where id = target and owner_id = (select auth.uid()))
 or exists(select 1 from public.team_members where team_id = target and user_id = (select auth.uid()));
$$;
create function private.can_access_project(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.projects p where p.id = target
 and (p.owner_id = (select auth.uid()) or private.in_team(p.team_id)));
$$;
create function private.shares_team(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.team_members m where m.user_id = target and private.in_team(m.team_id));
$$;
revoke all on all functions in schema private from public;
grant execute on function private.owns_team(uuid), private.in_team(uuid), private.can_access_project(uuid), private.shares_team(uuid) to authenticated;

create function private.on_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id,name) values(new.id, left(coalesce(new.raw_user_meta_data->>'name',''),120));
 return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function private.on_auth_user();
create function private.on_team_created() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.team_members(team_id,user_id,role) values(new.id,new.owner_id,'owner');
 return new;
end;
$$;
create trigger on_team_created after insert on public.teams for each row execute function private.on_team_created();
create function private.before_project_update() returns trigger
language plpgsql set search_path = '' as $$
begin
 if new.owner_id <> old.owner_id or new.team_id is distinct from old.team_id then
  raise exception 'Project ownership and team cannot be changed';
 end if;
 new.created_at := old.created_at;
 new.updated_at := now();
 return new;
end;
$$;
create trigger before_project_update before update on public.projects for each row execute function private.before_project_update();
create function private.before_task_write() returns trigger
language plpgsql set search_path = '' as $$
begin
 if tg_op = 'UPDATE' then
  new.created_by := old.created_by;
  new.created_at := old.created_at;
 end if;
 if new.status = 'done' then
  if tg_op = 'UPDATE' and old.status = 'done' then new.completed_at := old.completed_at;
  else new.completed_at := now(); end if;
 else new.completed_at := null; end if;
 new.updated_at := now();
 return new;
end;
$$;
create trigger before_task_write before insert or update on public.tasks for each row execute function private.before_task_write();
-- Trigger functions never need direct client execution.
revoke all on function private.on_auth_user(), private.on_team_created(), private.before_project_update(), private.before_task_write() from public;

alter table public.profiles enable row level security;
alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.projects enable row level security;
alter table public.tasks enable row level security;
alter table public.reports enable row level security;
revoke all on public.profiles, public.teams, public.team_members, public.projects, public.tasks, public.reports from anon;
grant select, insert, update, delete on public.profiles, public.teams, public.team_members, public.projects, public.tasks, public.reports to authenticated;

create policy profiles_read on public.profiles for select to authenticated using (id = (select auth.uid()) or private.shares_team(id));
create policy profiles_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy teams_read on public.teams for select to authenticated using (private.in_team(id));
create policy teams_insert on public.teams for insert to authenticated with check (owner_id = (select auth.uid()));
create policy teams_update on public.teams for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy teams_delete on public.teams for delete to authenticated using (owner_id = (select auth.uid()));
create policy members_read on public.team_members for select to authenticated using (private.in_team(team_id));
create policy members_insert on public.team_members for insert to authenticated with check (private.owns_team(team_id) and role = 'member' and user_id <> (select auth.uid()));
create policy members_delete on public.team_members for delete to authenticated using (private.owns_team(team_id) and role = 'member');
create policy projects_read on public.projects for select to authenticated using (owner_id = (select auth.uid()) or private.in_team(team_id));
create policy projects_insert on public.projects for insert to authenticated with check (owner_id = (select auth.uid()) and (team_id is null or private.owns_team(team_id)));
create policy projects_update on public.projects for update to authenticated using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy projects_delete on public.projects for delete to authenticated using (owner_id = (select auth.uid()));
create policy tasks_read on public.tasks for select to authenticated using (private.can_access_project(project_id));
create policy tasks_insert on public.tasks for insert to authenticated with check (private.can_access_project(project_id) and created_by = (select auth.uid()));
create policy tasks_update on public.tasks for update to authenticated using (private.can_access_project(project_id)) with check (private.can_access_project(project_id));
create policy tasks_delete on public.tasks for delete to authenticated using (private.can_access_project(project_id));
create policy reports_read on public.reports for select to authenticated using (private.can_access_project(project_id));
create policy reports_insert on public.reports for insert to authenticated with check (private.can_access_project(project_id) and created_by = (select auth.uid()));
create policy reports_delete on public.reports for delete to authenticated using (private.can_access_project(project_id) and created_by = (select auth.uid()));
