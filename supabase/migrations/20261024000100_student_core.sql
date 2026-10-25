-- Additive Students repository. No existing PM table, key, or data is changed.
-- Apply to the separately configured student Supabase instance after review.

create function public.student_valid_assignment(data jsonb, owner_id uuid, assignment_id uuid)
returns boolean language plpgsql immutable set search_path = '' as $$
declare material jsonb; item jsonb;
begin
  if jsonb_typeof(data) is distinct from 'object'
    or length(btrim(coalesce(data->>'title',''))) not between 1 and 200
    or length(coalesce(data->>'description','')) > 2000
    or coalesce(data->>'status','') not in ('todo','inProgress','done')
    or jsonb_typeof(data->'checklist') is distinct from 'array'
    or jsonb_typeof(data->'materials') is distinct from 'array'
    or jsonb_array_length(data->'materials') > 50
    or jsonb_array_length(data->'checklist') > 200
    or coalesce(data->>'dueAt','') = '' then return false; end if;
  perform (data->>'dueAt')::timestamptz;
  if data->>'completedAt' is not null then perform (data->>'completedAt')::timestamptz; end if;
  if data->>'reminderMinutes' is not null and
    ((data->>'reminderMinutes')::integer not between 0 and 525600) then return false; end if;
  for item in select * from jsonb_array_elements(data->'checklist') loop
    if length(btrim(coalesce(item->>'title',''))) not between 1 and 500
      or jsonb_typeof(item->'done') is distinct from 'boolean'
      or length(coalesce(item->>'id','')) = 0 then return false; end if;
  end loop;
  for material in select * from jsonb_array_elements(data->'materials') loop
    if length(btrim(coalesce(material->>'name',''))) not between 1 and 160
      or length(coalesce(material->>'id','')) = 0
      or material->>'bytes' is not null then return false; end if;
    if material->>'url' is not null then
      if length(material->>'url') > 2048
        or (material->>'url') !~* '^https?://[^[:space:]/@]+'
        or material->>'storagePath' is not null then return false; end if;
    else
      if coalesce(material->>'storagePath','') not like owner_id::text || '/' || assignment_id::text || '/%'
        or coalesce((material->>'byteLength')::bigint,-1) not between 0 and 2097152 then return false; end if;
    end if;
  end loop;
  return true;
exception when others then return false;
end;
$$;

create table public.student_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(data) = 'object'),
  check (length(btrim(coalesce(data->>'name',''))) between 1 and 160),
  check ((data->>'course')::integer between 1 and 8),
  check ((data->>'subgroup')::integer between 1 and 20)
);
create table public.student_subjects (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  unique (id,user_id),
  check (jsonb_typeof(data) = 'object'),
  check (length(btrim(coalesce(data->>'name',''))) between 1 and 200)
);
create table public.student_classes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  unique (id,subject_id,user_id),
  foreign key (subject_id,user_id) references public.student_subjects(id,user_id) on delete restrict,
  check (jsonb_typeof(data) = 'object'),
  check (length(btrim(coalesce(data->>'title',''))) between 1 and 200),
  check ((data->>'endsAt')::timestamptz > (data->>'startsAt')::timestamptz)
);
create table public.student_assignments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null,
  class_id uuid,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  foreign key (subject_id,user_id) references public.student_subjects(id,user_id) on delete restrict,
  foreign key (class_id,subject_id,user_id) references public.student_classes(id,subject_id,user_id) on delete restrict,
  check (public.student_valid_assignment(data,user_id,id))
);
create index student_subject_owner on public.student_subjects(user_id);
create index student_class_owner on public.student_classes(user_id,subject_id);
create index student_assignment_owner on public.student_assignments(user_id,subject_id);

create function public.student_touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end;
$$;
create trigger student_profile_touch before update on public.student_profiles for each row execute function public.student_touch_updated_at();
create trigger student_subject_touch before update on public.student_subjects for each row execute function public.student_touch_updated_at();
create trigger student_class_touch before update on public.student_classes for each row execute function public.student_touch_updated_at();
create trigger student_assignment_touch before update on public.student_assignments for each row execute function public.student_touch_updated_at();

alter table public.student_profiles enable row level security;
alter table public.student_subjects enable row level security;
alter table public.student_classes enable row level security;
alter table public.student_assignments enable row level security;
revoke all on public.student_profiles, public.student_subjects, public.student_classes, public.student_assignments from anon, public;
grant select,insert,update,delete on public.student_profiles, public.student_subjects, public.student_classes, public.student_assignments to authenticated;
create policy student_profile_owner on public.student_profiles for all to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy student_subject_owner on public.student_subjects for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy student_class_owner on public.student_classes for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy student_assignment_owner on public.student_assignments for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

insert into storage.buckets(id,name,public,file_size_limit)
values ('student-materials','student-materials',false,2097152)
on conflict (id) do nothing;
-- Files use UID/assignmentUUID/randomUUID. Signed read URLs expire after 5 minutes.
create policy student_file_read on storage.objects for select to authenticated using
  (bucket_id = 'student-materials' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy student_file_insert on storage.objects for insert to authenticated with check
  (bucket_id = 'student-materials' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy student_file_update on storage.objects for update to authenticated using
  (bucket_id = 'student-materials' and (storage.foldername(name))[1] = (select auth.uid())::text) with check
  (bucket_id = 'student-materials' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy student_file_delete on storage.objects for delete to authenticated using
  (bucket_id = 'student-materials' and (storage.foldername(name))[1] = (select auth.uid())::text);
