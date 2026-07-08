-- =============================================================
-- 更新：后台板块列表改为「按专业分组」（返回 dept + block 对）
-- 只需重跑这一个函数即可（覆盖旧的 admin_list_blocks）
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================
create or replace function public.admin_list_blocks(p_admin text)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select coalesce(json_agg(t order by t.dept, t.block), '[]'::json) into v
  from (select distinct dept, block from catalog where block is not null and block <> '') t;
  return json_build_object('blocks', v);
end; $$;
