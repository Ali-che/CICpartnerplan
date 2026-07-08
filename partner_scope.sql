-- =============================================================
-- 升级：每校「开放范围」= 允许的 (专业 dept × 板块 block) 组合
-- 学校登入后，专业下拉与板块都只出现后台开放的
-- 依赖：partner_setup.sql + partner_admin.sql（或 partner_full.sql）
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================

-- 1) 开放范围表（一笔 = 某校允许的一个 专业+板块）
create table if not exists public.partner_scope (
  pin   text not null,
  dept  text not null,
  block text not null,
  primary key (pin, dept, block)
);
alter table public.partner_scope enable row level security;

-- 2) 学校登入：按 scope 过滤 catalog（该校无 scope = 全部开放）
create or replace function public.partner_authenticate(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_active boolean; v_has boolean; v_catalog json;
begin
  select active into v_active from partner_pins where pin = p_pin;
  if v_active is not true then return json_build_object('error','invalid_pin'); end if;
  select exists(select 1 from partner_scope where pin = p_pin) into v_has;
  select coalesce(json_agg(t), '[]'::json) into v_catalog
  from (
    select * from public.catalog c
    where (not v_has)
       or exists(select 1 from partner_scope s
                 where s.pin = p_pin and s.dept = c.dept and s.block = c.block)
  ) t;
  return json_build_object('catalog', v_catalog);
end; $$;

-- 3) 后台：取某校的开放范围
create or replace function public.admin_get_partner_scope(p_admin text, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.dept, t.block), '[]'::json) into v
  from (select dept, block from partner_scope where pin = p_pin) t;
  return json_build_object('scope', v);
end; $$;

-- 4) 后台：设定某校的开放范围（整组替换；传空数组 = 开放全部）
create or replace function public.admin_set_partner_scope(p_admin text, p_pin text, p_scope jsonb)
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  delete from partner_scope where pin = p_pin;
  if p_scope is not null then
    insert into partner_scope(pin, dept, block)
    select p_pin, (e->>'dept'), (e->>'block')
    from jsonb_array_elements(p_scope) e
    where coalesce(e->>'dept','') <> '' and coalesce(e->>'block','') <> ''
    on conflict do nothing;
  end if;
  return json_build_object('ok', true);
end; $$;

-- 5) 后台登入：每校带上开放范围统计
create or replace function public.admin_authenticate(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json) into v
  from (
    select p.pin, p.school_name, p.active, p.created_at,
      (select count(*) from partner_projects pp where pp.pin = p.pin) as project_count,
      (select count(*) from partner_scope s where s.pin = p.pin) as scope_count,
      (select count(distinct s.dept) from partner_scope s where s.pin = p.pin) as dept_count
    from partner_pins p
  ) t;
  return json_build_object('ok', true, 'partners', v);
end; $$;

grant execute on function public.admin_get_partner_scope(text,text) to anon;
grant execute on function public.admin_set_partner_scope(text,text,jsonb) to anon;
