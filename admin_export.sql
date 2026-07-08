-- =============================================================
-- 后台导出：管理员读取任一项目的完整内容（含勾选快照）
-- 依赖：partner_setup.sql + partner_admin.sql
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================
create or replace function public.admin_load_project(p_admin text, p_id uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v json;
begin
  if not admin_check(p_admin) then return json_build_object('error','invalid_admin'); end if;
  select row_to_json(t) into v from (
    select pp.id, pp.pin, p.school_name, pp.project_name, pp.dept, pp.version,
           pp.payload, pp.updated_at
    from partner_projects pp
    left join partner_pins p on p.pin = pp.pin
    where pp.id = p_id
  ) t;
  return coalesce(v, json_build_object('error','not_found'));
end; $$;

grant execute on function public.admin_load_project(text,uuid) to anon;
