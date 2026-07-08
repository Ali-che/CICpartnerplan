-- =============================================================
-- 校校合作 Partner Course Planner · 完整建置 SQL（最新版，全部合一）
-- 从零建整套：合作校帐号 + 板块白名单 + 保存项目 + 管理员后台 + 导出
-- 不改动 catalog / authenticate / 排课系统
-- 幂等：可重复整段跑。贴进 Supabase → SQL Editor → Run
-- =============================================================

-- ========== 表 ==========
create table if not exists public.partner_pins (
  pin            text primary key,
  school_name    text,
  active         boolean not null default true,
  allowed_blocks text[],                                -- null=全部板块可选
  created_at     timestamptz not null default now()
);
alter table public.partner_pins add column if not exists allowed_blocks text[];
alter table public.partner_pins enable row level security;

create table if not exists public.partner_projects (
  id           uuid primary key default gen_random_uuid(),
  pin          text not null,
  school_name  text, project_name text, dept text, version text,
  payload      jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.partner_projects enable row level security;

create table if not exists public.app_admins (
  admin_pin  text primary key,
  name       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;

create table if not exists public.partner_scope (   -- 每校开放范围：专业×板块
  pin   text not null,
  dept  text not null,
  block text not null,
  primary key (pin, dept, block)
);
alter table public.partner_scope enable row level security;

-- ========== 内部：验管理员 ==========
create or replace function public.admin_check(p_admin text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists(select 1 from app_admins where admin_pin = p_admin and active);
$$;

-- ========== 学校端：登入并读 catalog（按白名单过滤）==========
create or replace function public.partner_authenticate(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_active boolean; v_has boolean; v_catalog json;
begin
  select active into v_active from partner_pins where pin = p_pin;
  if v_active is not true then return json_build_object('error','invalid_pin'); end if;
  select exists(select 1 from partner_scope where pin = p_pin) into v_has;
  select coalesce(json_agg(t), '[]'::json) into v_catalog
  from ( select * from public.catalog c
         where (not v_has)
            or exists(select 1 from partner_scope s
                      where s.pin = p_pin and s.dept = c.dept and s.block = c.block) ) t;
  return json_build_object('catalog', v_catalog);
end; $$;

-- ========== 学校端：保存 / 列出 / 载入 / 删除 项目 ==========
create or replace function public.partner_save_project(
  p_pin text, p_id uuid, p_school text, p_project text,
  p_dept text, p_version text, p_payload jsonb
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v_id uuid;
begin
  select exists(select 1 from partner_pins where pin=p_pin and active) into v_ok;
  if not v_ok then raise exception 'invalid_pin'; end if;
  if p_id is null then
    insert into partner_projects(pin,school_name,project_name,dept,version,payload)
    values(p_pin,p_school,p_project,p_dept,p_version,coalesce(p_payload,'[]'::jsonb))
    returning id into v_id;
  else
    update partner_projects set school_name=p_school,project_name=p_project,dept=p_dept,
      version=p_version,payload=coalesce(p_payload,'[]'::jsonb),updated_at=now()
      where id=p_id and pin=p_pin returning id into v_id;
    if v_id is null then raise exception 'not_found_or_forbidden'; end if;
  end if;
  return v_id;
end; $$;

create or replace function public.partner_list_projects(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v json;
begin
  select exists(select 1 from partner_pins where pin=p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  select coalesce(json_agg(t order by t.updated_at desc),'[]'::json) into v
  from (select id,school_name,project_name,dept,version,updated_at,
               jsonb_array_length(payload) as course_count
        from partner_projects where pin=p_pin) t;
  return json_build_object('projects',v);
end; $$;

create or replace function public.partner_load_project(p_pin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; v json;
begin
  select exists(select 1 from partner_pins where pin=p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  select row_to_json(t) into v from (
    select id,school_name,project_name,dept,version,payload,updated_at
    from partner_projects where id=p_id and pin=p_pin) t;
  return coalesce(v, json_build_object('error','not_found'));
end; $$;

create or replace function public.partner_delete_project(p_pin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_ok boolean; n int;
begin
  select exists(select 1 from partner_pins where pin=p_pin and active) into v_ok;
  if not v_ok then return json_build_object('error','invalid_pin'); end if;
  delete from partner_projects where id=p_id and pin=p_pin;
  get diagnostics n = row_count;
  return json_build_object('deleted',n);
end; $$;

-- ========== 管理员后台 ==========
create or replace function public.admin_authenticate(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.created_at desc),'[]'::json) into v
  from (select p.pin,p.school_name,p.active,p.created_at,
               (select count(*) from partner_projects pp where pp.pin=p.pin) as project_count,
               (select count(*) from partner_scope s where s.pin=p.pin) as scope_count,
               (select count(distinct s.dept) from partner_scope s where s.pin=p.pin) as dept_count
        from partner_pins p) t;
  return json_build_object('ok',true,'partners',v);
end; $$;

create or replace function public.admin_add_partner(p_admin text, p_pin text, p_school text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  if p_pin is null or length(trim(p_pin))=0 then return json_build_object('error','empty_pin'); end if;
  insert into partner_pins(pin,school_name) values(trim(p_pin),p_school)
    on conflict (pin) do update set school_name=excluded.school_name;
  return json_build_object('ok',true);
end; $$;

create or replace function public.admin_set_partner_active(p_admin text, p_pin text, p_active boolean)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  update partner_pins set active=p_active where pin=p_pin;
  return json_build_object('ok',true);
end; $$;

create or replace function public.admin_delete_partner(p_admin text, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  delete from partner_projects where pin=p_pin;
  delete from partner_pins where pin=p_pin;
  return json_build_object('ok',true);
end; $$;

create or replace function public.admin_list_all_projects(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.updated_at desc),'[]'::json) into v
  from (select pp.id,pp.pin,p.school_name,pp.project_name,pp.dept,pp.version,
               jsonb_array_length(pp.payload) as course_count,pp.updated_at
        from partner_projects pp left join partner_pins p on p.pin=pp.pin) t;
  return json_build_object('projects',v);
end; $$;

-- 板块（后台勾选界面：按专业分组）
create or replace function public.admin_list_blocks(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.dept, t.block),'[]'::json) into v
  from (select distinct dept, block from catalog where block is not null and block <> '') t;
  return json_build_object('blocks',v);
end; $$;

create or replace function public.admin_get_partner_scope(p_admin text, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.dept,t.block),'[]'::json) into v
  from (select dept,block from partner_scope where pin=p_pin) t;
  return json_build_object('scope',v);
end; $$;

create or replace function public.admin_set_partner_scope(p_admin text, p_pin text, p_scope jsonb)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  delete from partner_scope where pin=p_pin;
  if p_scope is not null then
    insert into partner_scope(pin,dept,block)
    select p_pin,(e->>'dept'),(e->>'block') from jsonb_array_elements(p_scope) e
    where coalesce(e->>'dept','')<>'' and coalesce(e->>'block','')<>''
    on conflict do nothing;
  end if;
  return json_build_object('ok',true);
end; $$;

-- 后台导出：读任一项目
create or replace function public.admin_load_project(p_admin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select row_to_json(t) into v from (
    select pp.id,pp.pin,p.school_name,pp.project_name,pp.dept,pp.version,pp.payload,pp.updated_at
    from partner_projects pp left join partner_pins p on p.pin=pp.pin
    where pp.id=p_id) t;
  return coalesce(v, json_build_object('error','not_found'));
end; $$;

-- ========== 授权匿名（publishable key）调用 ==========
grant execute on function public.partner_authenticate(text) to anon;
grant execute on function public.partner_save_project(text,uuid,text,text,text,text,jsonb) to anon;
grant execute on function public.partner_list_projects(text) to anon;
grant execute on function public.partner_load_project(text,uuid) to anon;
grant execute on function public.partner_delete_project(text,uuid) to anon;
grant execute on function public.admin_authenticate(text) to anon;
grant execute on function public.admin_add_partner(text,text,text) to anon;
grant execute on function public.admin_set_partner_active(text,text,boolean) to anon;
grant execute on function public.admin_delete_partner(text,text) to anon;
grant execute on function public.admin_list_all_projects(text) to anon;
grant execute on function public.admin_list_blocks(text) to anon;
grant execute on function public.admin_get_partner_scope(text,text) to anon;
grant execute on function public.admin_set_partner_scope(text,text,jsonb) to anon;
grant execute on function public.admin_load_project(text,uuid) to anon;

-- ========== 初始帐号（务必改成你自己的强 PIN）==========
insert into public.app_admins(admin_pin,name) values('ADMIN-0000','管理员')
  on conflict (admin_pin) do nothing;
insert into public.partner_pins(pin,school_name) values('PARTNER-1234','示例大学')
  on conflict (pin) do nothing;
-- 管理员登入：ADMIN-0000 ｜ 学校登入：PARTNER-1234（都请尽快改掉）
