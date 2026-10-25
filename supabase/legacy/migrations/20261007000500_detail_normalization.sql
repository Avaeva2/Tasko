-- Keep labels a flat array so the Flutter List<String> contract stays valid.
create or replace function private.valid_task_labels(value text[]) returns boolean
language sql immutable strict set search_path = '' as $$
 select coalesce(array_ndims(value), 1) = 1 and cardinality(value) <= 5
 and not exists(select 1 from unnest(value) label where label is null or char_length(label) not between 1 and 24 or label <> trim(label))
 and cardinality(value) = (select count(distinct label) from unnest(value) label);
$$;

create or replace function private.before_subtask_write() returns trigger
language plpgsql set search_path = '' as $$
begin
 new.title := trim(new.title);
 if tg_op = 'UPDATE' then
  if new.task_id <> old.task_id or new.id <> old.id then raise exception 'Subtask parent cannot be changed'; end if;
  new.created_at := old.created_at;
 else new.created_at := now(); end if;
 new.updated_at := now();
 return new;
end;
$$;

create or replace function private.before_comment_insert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.author_id is distinct from auth.uid() or new.author_name <> '' then
  raise exception 'Comment author is server-controlled' using errcode = '42501';
 end if;
 select coalesce(nullif(trim(name), ''), 'Участник Tasko') into new.author_name from public.profiles where id = (select auth.uid());
 new.author_name := coalesce(new.author_name, 'Участник Tasko');
 new.body := trim(new.body);
 new.created_at := now();
 return new;
end;
$$;
