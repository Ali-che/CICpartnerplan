-- =============================================================
-- 板块白名单：每个合作校帐号能选哪些板块（block）
-- 空/未设 = 全部板块可选；有设 = 只开放勾选的板块
-- 依赖：已跑过 partner_setup.sql 与 partner_admin.sql
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================

-- 1) 给合作校帐号加「允许的板块」栏（text 数组；null = 全部）
alter table public.partner_pins
  add column if not exists allowed_blocks text[];

-- 2) 重建学校登入：按该校白名单过滤 catalog 再返回
create or replace function public.partner_authenticate(p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare v_active boolean; v_blocks text[]; v_catalog json;
begin
  select active, allowed_blocks into v_active, v_blocks
  from partner_pins where pin = p_pin;

  if v_active is not true then
    return json_build_object('error','invalid_pin');
  end if;

  select coalesce(json_agg(t), '[]'::json) into v_catalog
  from (
    select * from public.catalog
    where v_blocks is null
       or array_length(v_blocks,1) is null
       or block = any(v_blocks)
  ) t;

  return json_build_object('catalog', v_catalog);
end; $$;

-- 3) 后台：列出 catalog 里全部不重复的板块（给勾选界面用）
create or replace function public.admin_list_blocks(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(b order by b), '[]'::json) into v
  from (select distinct block as b from catalog where block is not null and block <> '') s;
  return json_build_object('blocks', v);
end; $$;

-- 4) 后台：设定某校允许的板块（传空数组 = 恢复全部可选）
create or replace function public.admin_set_partner_blocks(p_admin text, p_pin text, p_blocks text[])
returns json language plpgsql security definer set search_path = public as $$
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  update partner_pins
     set allowed_blocks = case
           when p_blocks is null or array_length(p_blocks,1) is null then null
           else p_blocks end
   where pin = p_pin;
  return json_build_object('ok', true);
end; $$;

-- 5) 重建后台登入：返回各校时带上 allowed_blocks
create or replace function public.admin_authenticate(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.created_at desc), '[]'::json) into v
  from (
    select p.pin, p.school_name, p.active, p.allowed_blocks, p.created_at,
           (select count(*) from partner_projects pp where pp.pin = p.pin) as project_count
    from partner_pins p
  ) t;
  return json_build_object('ok', true, 'partners', v);
end; $$;

grant execute on function public.admin_list_blocks(text) to anon;
grant execute on function public.admin_set_partner_blocks(text,text,text[]) to anon;
