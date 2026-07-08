-- =============================================================
-- 合作项目课程勾选系统 · 数据库建表 + 权限（Supabase / PostgreSQL）
-- 直接贴进 Supabase → SQL Editor → Run 即可
-- =============================================================

-- ---------- 0. 角色档案 profiles ----------
-- 每个登入者一笔：admin(你/后台) 或 school(学校老师)
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          text not null default 'school' check (role in ('admin','school')),
  school_name   text,                       -- 学校老师所属学校
  display_name  text,
  created_at    timestamptz not null default now()
);

-- 新用户注册时自动建一笔 profile（默认 school）
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 判断当前用户是不是管理员（RLS 里反复用到）
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;


-- ---------- 1. 课程库 courses（母数据，只读给学校端）----------
create table if not exists public.courses (
  id             uuid primary key default gen_random_uuid(),
  major_name_zh  text not null,             -- 专业中文名
  major_name_en  text,                      -- 专业英文名
  academic_year  text not null,             -- 适用学年课纲，如 '114'
  category_title text not null,             -- 课程大标题 / 模块
  course_name_zh text not null,             -- 课程中文名
  course_name_en text,                      -- 课程英文名
  credits        numeric(4,1) not null default 0,   -- 学分（允许 0.5 之类）
  sort_order     int default 0,
  created_at     timestamptz not null default now()
);
create index if not exists idx_courses_lookup
  on public.courses (academic_year, major_name_zh, category_title, sort_order);


-- ---------- 2. 合作项目 projects ----------
create table if not exists public.projects (
  id            uuid primary key default gen_random_uuid(),
  school_name   text not null,              -- 合作项目学校名称
  project_name  text not null,              -- 合作项目名称
  academic_year text not null,              -- 适用学年课纲
  created_by    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now()
);
create index if not exists idx_projects_owner on public.projects (created_by);


-- ---------- 3. 勾选纪录 project_courses（多对多）----------
create table if not exists public.project_courses (
  project_id  uuid not null references public.projects(id) on delete cascade,
  course_id   uuid not null references public.courses(id) on delete restrict,
  sort_order  int default 0,
  created_at  timestamptz not null default now(),
  primary key (project_id, course_id)       -- 一门课在一个项目里只勾一次
);
create index if not exists idx_pc_project on public.project_courses (project_id);


-- =============================================================
-- 4. 行级权限 RLS —— 每校只看得到自己的项目
-- =============================================================
alter table public.profiles        enable row level security;
alter table public.courses         enable row level security;
alter table public.projects        enable row level security;
alter table public.project_courses enable row level security;

-- profiles：看自己 / 管理员看全部
create policy profiles_self_read on public.profiles
  for select using (id = auth.uid() or public.is_admin());
create policy profiles_admin_write on public.profiles
  for all using (public.is_admin()) with check (public.is_admin());

-- courses：所有登入者可读；只有管理员能改
create policy courses_read on public.courses
  for select to authenticated using (true);
create policy courses_admin_write on public.courses
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- projects：本人或管理员，可读可改
create policy projects_owner_all on public.projects
  for all to authenticated
  using (created_by = auth.uid() or public.is_admin())
  with check (created_by = auth.uid() or public.is_admin());

-- project_courses：能不能碰，取决于所属 project 是否属于自己
create policy pc_owner_all on public.project_courses
  for all to authenticated
  using (exists (
    select 1 from public.projects p
    where p.id = project_courses.project_id
      and (p.created_by = auth.uid() or public.is_admin())))
  with check (exists (
    select 1 from public.projects p
    where p.id = project_courses.project_id
      and (p.created_by = auth.uid() or public.is_admin())));


-- =============================================================
-- 5. 生成「课程架构表」用的视图（前端直接查，已带明细）
-- =============================================================
create or replace view public.v_project_structure as
select
  pc.project_id,
  c.major_name_zh,
  c.major_name_en,
  c.academic_year,
  c.category_title,
  c.course_name_zh,
  c.course_name_en,
  c.credits,
  pc.sort_order
from public.project_courses pc
join public.courses c on c.id = pc.course_id;
-- 前端： select * from v_project_structure where project_id = :id
--       order by major_name_zh, category_title, sort_order;
-- 分组、小计、专业合计、全项目合计 在前端算（或用 GROUP BY ROLLUP）。


-- =============================================================
-- 6.（可选）示范数据 —— 想空跑测试就取消注释
-- =============================================================
-- insert into public.courses
--   (major_name_zh, major_name_en, academic_year, category_title, course_name_zh, course_name_en, credits, sort_order)
-- values
--   ('数字媒体设计','Digital Media Design','114','设计基础','设计概论','Introduction to Design',3,1),
--   ('数字媒体设计','Digital Media Design','114','设计基础','色彩构成','Color Composition',2,2),
--   ('数字媒体设计','Digital Media Design','114','数字技术','交互设计','Interaction Design',3,3),
--   ('商务英语','Business English','114','语言核心','综合英语','Integrated English',4,1);

-- 把某个用户设为管理员（把 UUID 换成 Supabase → Authentication 里的 user id）：
-- update public.profiles set role = 'admin' where id = '你的-user-uuid';
