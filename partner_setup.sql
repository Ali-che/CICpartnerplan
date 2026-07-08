-- =============================================================
-- 校校合作 Partner Course Planner · 一次性建置 SQL（最终版）
-- 已确认 catalog 表名，直接贴进 Supabase → SQL Editor → Run
-- 不改动 catalog、authenticate、排课任何东西
-- =============================================================

-- ========== A. 合作校独立 PIN + 只读 catalog ==========

-- A1) 合作校 PIN 表（每校一个，可随时启用/停用）
create table if not exists public.partner_pins (
  pin         text primary key,
  school_name text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table public.partner_pins enable row level security;   -- 不开策略 => 匿名 key 无法直接读

-- A2) 合作校登入：验独立 PIN → 只回 catalog（读不到排课数据）
create or replace function public.partner_authenticate(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v_catalog json;
begin
  select exists(select 1 from partner_pins where pin = p_pin and active) into v_ok;
  if not v_ok then
    return json_build_object('error','invalid_pin');
  end if;

  select coalesce(json_agg(t), '[]'::json) into v_catalog
  from ( select * from public.catalog ) t;

  return json_build_object('catalog', v_catalog);
end; $$;

revoke all on function public.partner_authenticate(text) from public;
grant execute on function public.partner_authenticate(text) to anon;


-- ========== B. 保存功能：项目 + 勾选快照 ==========

-- B1) 存储表（一笔 = 一个合作校项目）
create table if not exists public.partner_projects (
  id           uuid primary key default gen_random_uuid(),
  pin          text not null,
  school_name  text,
  project_name text,
  dept         text,
  version      text,
  payload      jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.partner_projects enable row level security;  -- 只经下面函数存取，按 PIN 隔离

-- B2) 保存（p_id 为空=新建，否则更新自己的）
create or replace function public.partner_save_project(
  p_pin text, p_id uuid, p_school text, p_project text,
  p_dept text, p_version text, p_payload jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
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

-- B3) 列出该 PIN 的项目
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

-- B4) 载入单个项目
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

-- B5) 删除
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

grant execute on function public.partner_save_project(text,uuid,text,text,text,text,jsonb) to anon;
grant execute on function public.partner_list_projects(text) to anon;
grant execute on function public.partner_load_project(text,uuid) to anon;
grant execute on function public.partner_delete_project(text,uuid) to anon;


-- ========== C. 加一个测试 PIN（自行改） ==========
insert into public.partner_pins (pin, school_name)
values ('PARTNER-1234', '示例大学')
on conflict (pin) do nothing;

-- 完成。登入用 PIN：PARTNER-1234
