-- =============================================================
-- 合作校专用登入 partner_authenticate
-- 独立 PIN，只返回 catalog（只读），与排课系统的 authenticate 完全分开
-- 不改动 catalog 本身
-- 贴进 Supabase → SQL Editor → Run
-- =============================================================

-- 1) 合作校 PIN 表（可每校一个，随时启用/停用）
create table if not exists public.partner_pins (
  pin         text primary key,
  school_name text,
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
alter table public.partner_pins enable row level security;
-- 不开任何 RLS 策略 => 匿名 key 无法直接读这张表（只有下面的函数以 definer 身份能读）

-- 2) 独立读取函数：验合作校 PIN → 只回 catalog
create or replace function public.partner_authenticate(p_pin text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
  v_catalog json;
begin
  -- 验合作校专属 PIN（跟排课 PIN 无关）
  select exists(
    select 1 from public.partner_pins
    where pin = p_pin and active
  ) into v_ok;

  if not v_ok then
    return json_build_object('error', 'invalid_pin');
  end if;

  -- ⬇️⬇️ 唯一需要你确认的地方：把下面这段换成你「真实 catalog 的来源」 ⬇️⬇️
  --
  --   情况 A：catalog 是一张独立表（例如就叫 catalog）
  --      select coalesce(json_agg(t), '[]'::json) into v_catalog
  --      from ( select * from public.catalog ) t;
  --
  --   情况 B：catalog 存在一张通用 records 表里，用 type 区分
  --      select coalesce(json_agg(t), '[]'::json) into v_catalog
  --      from ( select * from public.records where type = 'catalog' ) t;
  --
  --   情况 C：直接复用现有 authenticate 里读 catalog 的那段 SQL（最稳）
  --
  select coalesce(json_agg(t), '[]'::json) into v_catalog
  from ( select * from public.catalog ) t;   -- << 按你的实际来源改这一行
  -- ⬆️⬆️ ------------------------------------------------------- ⬆️⬆️

  return json_build_object('catalog', v_catalog);
end;
$$;

-- 3) 允许匿名（publishable key）调用这个函数
grant execute on function public.partner_authenticate(text) to anon;
revoke all on function public.partner_authenticate(text) from public;
grant execute on function public.partner_authenticate(text) to anon;

-- 4) 加一个合作校 PIN（自行改成你要的）
insert into public.partner_pins (pin, school_name)
values ('PARTNER-1234', '示例大学')
on conflict (pin) do nothing;

-- 之后要加/停用某校：
--   insert into partner_pins(pin, school_name) values ('校B的PIN','B大学');
--   update partner_pins set active = false where pin = 'PARTNER-1234';
