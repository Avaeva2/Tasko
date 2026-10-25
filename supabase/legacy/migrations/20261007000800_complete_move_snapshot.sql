-- A scalar JSON value bypasses the Data API row cap for the complete project
-- snapshot. Existing RPC permissions, locks, auth/RLS and move rules are kept.
drop function public.move_task(uuid,text,uuid);
create function public.move_task(p_task_id uuid,p_status text,p_before_task_id uuid default null)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare source public.tasks; target public.tasks; ordered uuid[]; existing uuid[]; insertion integer; old_flag text; old_target text; result jsonb;
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
  select coalesce(jsonb_agg(to_jsonb(t) order by t.status,t.position,t.id),'[]'::jsonb) into result from public.tasks t where t.project_id=source.project_id;
  return result;
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
  select coalesce(jsonb_agg(to_jsonb(t) order by t.status,t.position,t.id),'[]'::jsonb) into result from public.tasks t where t.project_id=source.project_id;
  return result;
 end if;
 old_flag := current_setting('tasko.rank_write',true); old_target := current_setting('tasko.rank_target',true);
 perform set_config('tasko.rank_write','on',true); perform set_config('tasko.rank_target',p_task_id::text,true);
 update public.tasks set status=p_status where id=p_task_id;
 update public.tasks t set position=r.rank::integer from unnest(ordered) with ordinality r(id,rank) where t.id=r.id and t.position<>r.rank;
 perform set_config('tasko.rank_write',coalesce(old_flag,'off'),true); perform set_config('tasko.rank_target',coalesce(old_target,''),true);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.status,t.position,t.id),'[]'::jsonb) into result from public.tasks t where t.project_id=source.project_id;
 return result;
end;
$$;
revoke all on function public.move_task(uuid,text,uuid) from public,anon;
grant execute on function public.move_task(uuid,text,uuid) to authenticated;
