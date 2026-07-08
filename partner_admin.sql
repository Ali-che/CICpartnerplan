-- =============================================================
-- 管理员后台 admin
-- 管理各合作校帐号（partner_pins）+ 总览所有项目
-- 依赖：已跑过 partner_setup.sql（需 partner_pins / partner_projects）
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================

-- 1) 管理员帐号表
create table if not exists public.app_admins (
  admin_pin  text primary key,
  name       text,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;   -- 只经下面 definer 函数验证

-- 2) 内部：验证是不是有效管理员
create or replace function public.admin_check(p_admin text)
returns boolean language sql security definer set search_path = public stable as $$
  select exists(select 1 from app_admins where admin_pin = p_admin and active);
$$;

-- 3) 管理员登入：返回全部合作校 + 各校项目数
create or replace function public.admin_authenticate(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json) into v
  from (
    select p.pin, p.school_name, p.active, p.created_at,
           (select count(*) from partner_projects pp where pp.pin = p.pin) as project_count
    from partner_pins p
  ) t;
  return json_build_object('ok', true, 'partners', v);
end; $$;

-- 4) 新增 / 改名 合作校帐号
create or replace function public.admin_add_partner(p_admin text, p_pin text, p_school text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  if p_pin is null or length(trim(p_pin)) = 0 then return json_build_object('error','empty_pin'); end if;
  insert into partner_pins(pin, school_name) values (trim(p_pin), p_school)
    on conflict (pin) do update set school_name = excluded.school_name;
  return json_build_object('ok', true);
end; $$;

-- 5) 启用 / 停用
create or replace function public.admin_set_partner_active(p_admin text, p_pin text, p_active boolean)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  update partner_pins set active = p_active where pin = p_pin;
  return json_build_object('ok', true);
end; $$;

-- 6) 删除合作校（连同其项目）
create or replace function public.admin_delete_partner(p_admin text, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  delete from partner_projects where pin = p_pin;
  delete from partner_pins where pin = p_pin;
  return json_build_object('ok', true);
end; $$;

-- 7) 总览所有项目（跨全部合作校）
create or replace function public.admin_list_all_projects(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.updated_at desc), '[]'::json) into v
  from (
    select pp.id, pp.pin, p.school_name, pp.project_name, pp.dept, pp.version,
           jsonb_array_length(pp.payload) as course_count, pp.updated_at
    from partner_projects pp
    left join partner_pins p on p.pin = pp.pin
  ) t;
  return json_build_object('projects', v);
end; $$;

-- 8) 授权匿名（publishable key）调用（真正的门槛是 admin_pin）
grant execute on function public.admin_authenticate(text) to anon;
grant execute on function public.admin_add_partner(text,text,text) to anon;
grant execute on function public.admin_set_partner_active(text,text,boolean) to anon;
grant execute on function public.admin_delete_partner(text,text) to anon;
grant execute on function public.admin_list_all_projects(text) to anon;

-- 9) 建一个管理员帐号（务必改成你自己的强 PIN）
insert into public.app_admins(admin_pin, name)
values ('ADMIN-0000', '管理员')
on conflict (admin_pin) do nothing;

-- 完成。管理员登入 PIN：ADMIN-0000（请尽快改掉）
