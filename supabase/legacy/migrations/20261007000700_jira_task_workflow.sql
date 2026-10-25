-- Additive issue types, monotonic numbers and per-column manual order.
alter table public.tasks add column issue_type text not null default 'task'
 check (issue_type in ('task', 'bug', 'story'));
alter table public.tasks add column issue_number bigint;
alter table public.tasks add column position integer not null default 0;
-- Backfill is metadata only; retain the user's original update timestamps.
alter table public.tasks disable trigger before_task_write;
with numbered as (
 select id, row_number() over (partition by project_id order by created_at,id) as number,
 row_number() over (partition by project_id,status order by created_at,id) as rank
 from public.tasks
)
update public.tasks t set issue_number=n.number, position=n.rank from numbered n where t.id=n.id;
alter table public.tasks enable trigger before_task_write;
alter table public.tasks alter column issue_number set not null;
alter table public.tasks add constraint tasks_issue_number_check check(issue_number > 0);
alter table public.tasks add constraint tasks_position_check check(position > 0);
alter table public.tasks add constraint tasks_project_number_unique unique(project_id,issue_number);
alter table public.tasks add constraint tasks_column_position_unique unique(project_id,status,position) deferrable initially deferred;

create table private.project_issue_counters (
 project_id uuid primary key references public.projects(id) on delete cascade,
 next_number bigint not null check(next_number > 0)
);
insert into private.project_issue_counters(project_id,next_number)
 select p.id,coalesce(max(t.issue_number),0)+1 from public.projects p
 left join public.tasks t on t.project_id=p.id group by p.id;
revoke all on private.project_issue_counters from public,anon,authenticated;

create function private.allocate_issue_number(target uuid) returns bigint
language plpgsql security definer set search_path = '' as $$
declare allocated bigint;
begin
 if auth.uid() is null or not private.can_access_project(target) then raise exception 'Project access denied' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || target::text,0));
 insert into private.project_issue_counters(project_id,next_number) values(target,2)
 on conflict(project_id) do update set next_number=private.project_issue_counters.next_number+1
 returning next_number-1 into allocated;
 return allocated;
end;
$$;
revoke all on function private.allocate_issue_number(uuid) from public,anon,authenticated;

create function private.before_task_identity_order() returns trigger
language plpgsql security definer set search_path = '' as $$
declare internal_rank boolean := coalesce(current_setting('tasko.rank_write',true),'off')='on';
begin
 if tg_op='INSERT' then
  if new.issue_number is not null or new.position <> 0 then raise exception 'Issue number and initial rank are server-controlled' using errcode='42501'; end if;
  new.issue_number := private.allocate_issue_number(new.project_id);
  select coalesce(max(position),0)+1 into new.position from public.tasks where project_id=new.project_id and status=new.status;
 else
  if new.issue_number is distinct from old.issue_number then raise exception 'Issue number is server-controlled' using errcode='42501'; end if;
  if new.position is distinct from old.position and not internal_rank then raise exception 'Use move_task for ranking' using errcode='42501'; end if;
  if new.project_id is distinct from old.project_id then
   -- Fixed lock order for cross-project edits; avoid requiring project UPDATE.
   perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || least(old.project_id::text,new.project_id::text),0));
   perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || greatest(old.project_id::text,new.project_id::text),0));
   new.issue_number := private.allocate_issue_number(new.project_id);
   select coalesce(max(position),0)+1 into new.position from public.tasks where project_id=new.project_id and status=new.status and id<>new.id;
  elsif new.status is distinct from old.status and not internal_rank then
   perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || new.project_id::text,0));
   select coalesce(max(position),0)+1 into new.position from public.tasks where project_id=new.project_id and status=new.status and id<>new.id;
  end if;
 end if;
 return new;
end;
$$;
revoke all on function private.before_task_identity_order() from public,anon,authenticated;
create trigger before_task_identity_order before insert or update on public.tasks for each row execute function private.before_task_identity_order();

create function public.move_task(p_task_id uuid,p_status text,p_before_task_id uuid default null)
returns setof public.tasks language plpgsql security invoker set search_path = '' as $$
declare source public.tasks; target public.tasks; ordered uuid[]; existing uuid[]; insertion integer; old_flag text; old_target text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_status is null or p_status not in ('todo','in_progress','review','blocked','done') then raise exception 'Invalid status' using errcode='22023'; end if;
 select * into source from public.tasks where id=p_task_id;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || source.project_id::text,0));
 select * into target from public.tasks where id=p_task_id;
 if not found or target.project_id<>source.project_id then raise exception 'Task changed. Refresh and retry' using errcode='22023'; end if;
 source := target;
 if p_before_task_id=p_task_id then
  return query select t.* from public.tasks t where t.project_id=source.project_id order by t.status,t.position,t.id;
  return;
 end if;
 if p_before_task_id is not null then
  select * into target from public.tasks where id=p_before_task_id and project_id=source.project_id and status=p_status;
  if not found then raise exception 'Ranking target unavailable' using errcode='22023'; end if;
 end if;
 select coalesce(array_agg(id order by position,id),'{}'::uuid[]) into existing from public.tasks where project_id=source.project_id and status=p_status;
 ordered := array_remove(existing,p_task_id);
 insertion := case when p_before_task_id is null then cardinality(ordered)+1 else array_position(ordered,p_before_task_id) end;
 ordered := coalesce(ordered[1:insertion-1],'{}'::uuid[]) || array[p_task_id] || coalesce(ordered[insertion:cardinality(ordered)],'{}'::uuid[]);
 if source.status=p_status and ordered=existing then
  return query select t.* from public.tasks t where t.project_id=source.project_id order by t.status,t.position,t.id;
  return;
 end if;
 old_flag := current_setting('tasko.rank_write',true); old_target := current_setting('tasko.rank_target',true);
 perform set_config('tasko.rank_write','on',true); perform set_config('tasko.rank_target',p_task_id::text,true);
 update public.tasks set status=p_status where id=p_task_id;
 update public.tasks t set position=r.rank::integer from unnest(ordered) with ordinality r(id,rank) where t.id=r.id and t.position<>r.rank;
 perform set_config('tasko.rank_write',coalesce(old_flag,'off'),true); perform set_config('tasko.rank_target',coalesce(old_target,''),true);
 return query select t.* from public.tasks t where t.project_id=source.project_id order by t.status,t.position,t.id;
end;
$$;

create function public.update_task(p_task_id uuid,p_project_id uuid,p_title text,p_description text,p_status text,p_priority text,p_due_date date,p_labels text[],p_issue_type text)
returns public.tasks language plpgsql security invoker set search_path = '' as $$
declare source public.tasks; current_source public.tasks; saved public.tasks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 select * into source from public.tasks where id=p_task_id;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 if p_project_id is null or not private.can_access_project(p_project_id) then raise exception 'Project access denied' using errcode='42501'; end if;
 -- Acquire project locks before UPDATE obtains any task row locks.
 perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || least(source.project_id::text,p_project_id::text),0));
 perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || greatest(source.project_id::text,p_project_id::text),0));
 select * into current_source from public.tasks where id=p_task_id;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 if current_source.project_id<>source.project_id then raise exception 'Task changed. Refresh and retry' using errcode='22023'; end if;
 update public.tasks set project_id=p_project_id,title=trim(p_title),description=trim(p_description),status=p_status,
 priority=p_priority,due_date=p_due_date,labels=p_labels,issue_type=p_issue_type where id=p_task_id returning * into saved;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 return saved;
end;
$$;

create function public.duplicate_task(p_task_id uuid,p_title text,p_include_subtasks boolean default true,p_copy_due_date boolean default false)
returns public.tasks language plpgsql security invoker set search_path = '' as $$
declare source public.tasks; current_source public.tasks; copied public.tasks; item public.task_subtasks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_title is null or char_length(trim(p_title)) not between 1 and 120 then raise exception 'Invalid title' using errcode='22023'; end if;
 select * into source from public.tasks where id=p_task_id;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended('tasko-project:' || source.project_id::text,0));
 select * into current_source from public.tasks where id=p_task_id;
 if not found then raise exception 'Task unavailable' using errcode='42501'; end if;
 if current_source.project_id<>source.project_id then raise exception 'Task changed. Refresh and retry' using errcode='22023'; end if;
 source := current_source;
 insert into public.tasks(project_id,title,description,status,priority,due_date,labels,issue_type)
 values(source.project_id,trim(p_title),source.description,'todo',source.priority,case when p_copy_due_date then source.due_date else null end,source.labels,source.issue_type)
 returning * into copied;
 if p_include_subtasks then
  for item in select * from public.task_subtasks where task_id=source.id order by created_at,id loop
   insert into public.task_subtasks(task_id,title,done) values(copied.id,item.title,false);
  end loop;
 end if;
 return copied;
end;
$$;
revoke all on function public.move_task(uuid,text,uuid),public.duplicate_task(uuid,text,boolean,boolean),public.update_task(uuid,uuid,text,text,text,text,date,text[],text) from public,anon;
grant execute on function public.move_task(uuid,text,uuid),public.duplicate_task(uuid,text,boolean,boolean),public.update_task(uuid,uuid,text,text,text,text,date,text[],text) to authenticated;

-- Preserve checklist chronology when several children are copied in one tx.
create or replace function private.before_subtask_write() returns trigger
language plpgsql set search_path = '' as $$
begin
 new.title := trim(new.title);
 if tg_op='UPDATE' then
  if new.task_id<>old.task_id or new.id<>old.id then raise exception 'Subtask parent cannot be changed'; end if;
  new.created_at := old.created_at;
 else new.created_at := clock_timestamp(); end if;
 new.updated_at := now(); return new;
end;
$$;

create or replace function private.log_task_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if tg_op='INSERT' then perform private.append_task_activity(new.id,'Создана задача «' || new.title || '»');
 else
  if new.status is distinct from old.status then perform private.append_task_activity(new.id,'Статус: «' || private.task_status_label(old.status) || '» → «' || private.task_status_label(new.status) || '»'); end if;
  if new.title is distinct from old.title then perform private.append_task_activity(new.id,'Изменено название задачи'); end if;
  if new.description is distinct from old.description then perform private.append_task_activity(new.id,'Изменено описание задачи'); end if;
  if new.due_date is distinct from old.due_date then perform private.append_task_activity(new.id,case when new.due_date is null then 'Срок задачи снят' else 'Срок задачи: ' || to_char(new.due_date,'DD.MM.YYYY') end); end if;
  if new.priority is distinct from old.priority then perform private.append_task_activity(new.id,'Изменён приоритет задачи'); end if;
  if new.labels is distinct from old.labels then perform private.append_task_activity(new.id,'Обновлены метки задачи'); end if;
  if new.project_id is distinct from old.project_id then perform private.append_task_activity(new.id,'Задача перенесена в другой проект'); end if;
  if new.issue_type is distinct from old.issue_type then perform private.append_task_activity(new.id,'Изменён тип задачи'); end if;
  if new.position is distinct from old.position and current_setting('tasko.rank_target',true)=new.id::text then perform private.append_task_activity(new.id,'Изменён порядок задачи'); end if;
 end if;
 return new;
end;
$$;
