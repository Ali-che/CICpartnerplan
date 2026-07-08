-- =============================================================
-- 合作校「保存项目」功能
-- 存储 + 保存/列出/载入/删除，全部绑合作校 PIN（各校只存取自己的）
-- 依赖：先跑过 partner_auth.sql（需要 partner_pins 表）
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================

-- 1) 存储表：一笔 = 一个合作校项目（含勾选课程的快照）
create table if not exists public.partner_projects (
  id           uuid primary key default gen_random_uuid(),
  pin          text not null,                         -- 哪个合作校 PIN 存的
  school_name  text,
  project_name text,
  dept         text,
  version      text,
  payload      jsonb not null default '[]'::jsonb,    -- 勾选课程快照（code/zh/en/credit/block/map…）
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.partner_projects enable row level security;
-- 不开 RLS 策略 => 匿名 key 不能直接读写这张表，只有下面的 definer 函数能（且按 PIN 隔离）

-- 2) 保存（p_id 为空=新建，否则更新自己的）
create or replace function public.partner_save_project(
  p_pin text, p_id uuid, p_school text, p_project text,
  p_dept text, p_version text, p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v_id uuid;
begin
  select exists(select 1 from partner_pins where pin = p_pin and active) into v_ok;
  if not v_ok then raise exception 'invalid_pin'; end if;

  if p_id is null then
    insert into partner_projects(pin, school_name, project_name, dept, version, payload)
    values (p_pin, p_school, p_project, p_dept, p_version, coalesce(p_payload,'[]'::jsonb))
    returning id into v_id;
  else
    update partner_projects
       set school_name=p_school, project_name=p_project, dept=p_dept, version=p_version,
           payload=coalesce(p_payload,'[]'::jsonb), updated_at=now()
     where id = p_id and pin = p_pin
    returning id into v_id;
    if v_id is null then raise exception 'not_found_or_forbidden'; end if;
  end if;
  return v_id;
end; $$;

-- 3) 列出该 PIN 的项目（不含 payload，轻量）
create or replace function public.partner_list_projects(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v json;
begin
  select exists(select 1 from partner_pins where pin = p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  select coalesce(json_agg(t order by t.updated_at desc), '[]'::json) into v
  from (
    select id, school_name, project_name, dept, version, updated_at,
           jsonb_array_length(payload) as course_count
    from partner_projects where pin = p_pin
  ) t;
  return json_build_object('projects', v);
end; $$;

-- 4) 载入单个项目（含 payload）
create or replace function public.partner_load_project(p_pin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v json;
begin
  select exists(select 1 from partner_pins where pin = p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  select row_to_json(t) into v from (
    select id, school_name, project_name, dept, version, payload, updated_at
    from partner_projects where id = p_id and pin = p_pin
  ) t;
  return coalesce(v, json_build_object('error','not_found'));
end; $$;

-- 5) 删除
create or replace function public.partner_delete_project(p_pin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; n int;
begin
  select exists(select 1 from partner_pins where pin = p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  delete from partner_projects where id = p_id and pin = p_pin;
  get diagnostics n = row_count;
  return json_build_object('deleted', n);
end; $$;

-- 6) 授权匿名（publishable key）调用
grant execute on function public.partner_save_project(text,uuid,text,text,text,text,jsonb) to anon;
grant execute on function public.partner_list_projects(text) to anon;
grant execute on function public.partner_load_project(text,uuid) to anon;
grant execute on function public.partner_delete_project(text,uuid) to anon;
