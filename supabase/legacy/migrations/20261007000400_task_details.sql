-- Additive task details; task/project RLS remains the access authority.
create function private.valid_task_labels(value text[]) returns boolean
language sql immutable strict set search_path = '' as $$
 select cardinality(value) <= 5
 and not exists(select 1 from unnest(value) label where label is null or char_length(label) not between 1 and 24 or label <> trim(label))
 and cardinality(value) = (select count(distinct label) from unnest(value) label);
$$;
revoke all on function private.valid_task_labels(text[]) from public;
grant execute on function private.valid_task_labels(text[]) to authenticated;
alter table public.tasks add column labels text[] not null default '{}';
alter table public.tasks add constraint tasks_labels_check check(private.valid_task_labels(labels));

create table public.task_subtasks (
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.tasks(id) on delete cascade,
 title text not null check(char_length(trim(title)) between 1 and 120),
 done boolean not null default false,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.task_comments (
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.tasks(id) on delete cascade,
 author_id uuid references auth.users(id) on delete set null default auth.uid(),
 author_name text not null default '',
 body text not null check(char_length(trim(body)) between 1 and 2000),
 created_at timestamptz not null default now()
);
create table public.task_activities (
 id uuid primary key default gen_random_uuid(),
 task_id uuid not null references public.tasks(id) on delete cascade,
 actor_id uuid references auth.users(id) on delete set null,
 actor_name text not null,
 body text not null check(char_length(body) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index task_subtasks_task on public.task_subtasks(task_id, created_at);
create index task_comments_task on public.task_comments(task_id, created_at);
create index task_activities_task on public.task_activities(task_id, created_at);

create function private.can_access_task(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.tasks where id = target and private.can_access_project(project_id));
$$;
revoke all on function private.can_access_task(uuid) from public;
grant execute on function private.can_access_task(uuid) to authenticated;
alter table public.task_subtasks enable row level security;
alter table public.task_comments enable row level security;
alter table public.task_activities enable row level security;
revoke all on public.task_subtasks, public.task_comments, public.task_activities from anon, authenticated;
grant select, insert, update, delete on public.task_subtasks to authenticated;
grant select, insert on public.task_comments to authenticated;
grant select on public.task_activities to authenticated;
create policy subtasks_read on public.task_subtasks for select to authenticated using(private.can_access_task(task_id));
create policy subtasks_insert on public.task_subtasks for insert to authenticated with check(private.can_access_task(task_id));
create policy subtasks_update on public.task_subtasks for update to authenticated using(private.can_access_task(task_id)) with check(private.can_access_task(task_id));
create policy subtasks_delete on public.task_subtasks for delete to authenticated using(private.can_access_task(task_id));
create policy comments_read on public.task_comments for select to authenticated using(private.can_access_task(task_id));
create policy comments_insert on public.task_comments for insert to authenticated with check(private.can_access_task(task_id) and author_id = (select auth.uid()));
create policy activities_read on public.task_activities for select to authenticated using(private.can_access_task(task_id));

create function private.task_status_label(value text) returns text
language sql immutable strict set search_path = '' as $$
 select case value when 'todo' then 'К выполнению' when 'in_progress' then 'В работе' when 'review' then 'На ревью' when 'blocked' then 'Заблокировано' when 'done' then 'Готово' else value end;
$$;
create function private.append_task_activity(target uuid, event_body text) returns void
language plpgsql security definer set search_path = '' as $$
declare who text;
begin
 select nullif(trim(name), '') into who from public.profiles where id = (select auth.uid());
 insert into public.task_activities(task_id, actor_id, actor_name, body)
 values(target, (select auth.uid()), coalesce(who, case when auth.uid() is null then 'Система' else 'Участник Tasko' end), event_body);
end;
$$;
create function private.log_task_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if tg_op = 'INSERT' then
  perform private.append_task_activity(new.id, 'Создана задача «' || new.title || '»');
 else
  if new.status is distinct from old.status then
   perform private.append_task_activity(new.id, 'Статус: «' || private.task_status_label(old.status) || '» → «' || private.task_status_label(new.status) || '»');
  end if;
  if new.title is distinct from old.title then perform private.append_task_activity(new.id, 'Изменено название задачи'); end if;
  if new.description is distinct from old.description then perform private.append_task_activity(new.id, 'Изменено описание задачи'); end if;
  if new.due_date is distinct from old.due_date then perform private.append_task_activity(new.id, case when new.due_date is null then 'Срок задачи снят' else 'Срок задачи: ' || to_char(new.due_date, 'DD.MM.YYYY') end); end if;
  if new.priority is distinct from old.priority then perform private.append_task_activity(new.id, 'Изменён приоритет задачи'); end if;
  if new.labels is distinct from old.labels then perform private.append_task_activity(new.id, 'Обновлены метки задачи'); end if;
  if new.project_id is distinct from old.project_id then perform private.append_task_activity(new.id, 'Задача перенесена в другой проект'); end if;
 end if;
 return new;
end;
$$;
create trigger task_activity after insert or update on public.tasks for each row execute function private.log_task_change();

create function private.before_subtask_write() returns trigger
language plpgsql set search_path = '' as $$
begin
 if tg_op = 'UPDATE' then
  if new.task_id <> old.task_id or new.id <> old.id then raise exception 'Subtask parent cannot be changed'; end if;
  new.created_at := old.created_at;
 else new.created_at := now(); end if;
 new.updated_at := now();
 return new;
end;
$$;
create trigger before_subtask_write before insert or update on public.task_subtasks for each row execute function private.before_subtask_write();
create function private.log_subtask_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if tg_op = 'INSERT' then
  perform private.append_task_activity(new.task_id, 'Добавлена подзадача «' || new.title || '»');
 elsif tg_op = 'UPDATE' then
  if new.done is distinct from old.done then perform private.append_task_activity(new.task_id, case when new.done then 'Выполнена подзадача «' else 'Открыта повторно подзадача «' end || new.title || '»'); end if;
  if new.title is distinct from old.title then perform private.append_task_activity(new.task_id, 'Изменено название подзадачи'); end if;
 else
  -- Parent deletion cascades: do not recreate an activity for a deleted task.
  if exists(select 1 from public.tasks where id = old.task_id) then perform private.append_task_activity(old.task_id, 'Удалена подзадача «' || old.title || '»'); end if;
  return old;
 end if;
 return new;
end;
$$;
create trigger subtask_activity after insert or update or delete on public.task_subtasks for each row execute function private.log_subtask_change();
create function private.before_comment_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.author_id is distinct from auth.uid() or new.author_name <> '' then
  raise exception 'Comment author is server-controlled' using errcode = '42501';
 end if;
 select coalesce(nullif(trim(name), ''), 'Участник Tasko') into new.author_name from public.profiles where id = (select auth.uid());
 new.author_name := coalesce(new.author_name, 'Участник Tasko');
 new.created_at := now();
 return new;
end;
$$;
create trigger before_comment_insert before insert on public.task_comments for each row execute function private.before_comment_insert();
create function private.log_comment_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 perform private.append_task_activity(new.task_id, 'Добавлен комментарий');
 return new;
end;
$$;
create trigger comment_activity after insert on public.task_comments for each row execute function private.log_comment_insert();
revoke all on function private.task_status_label(text), private.append_task_activity(uuid,text), private.log_task_change(), private.before_subtask_write(), private.log_subtask_change(), private.before_comment_insert(), private.log_comment_insert() from public, authenticated;
