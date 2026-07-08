# Partner Course Planner · 校校合作课程规划系统

合作校老师从课程库（Supabase `catalog`）勾选课程，自动生成分专业、分模块、带对接（articulation）的**课程架构表**，可导出 PDF。含管理员后台。

线上：<https://ali-che.github.io/CICpartnerplan/>

---

## 入口与登入

统一登入页，输 PIN 自动分流：

| 角色 | 网址 | 测试 PIN |
|------|------|----------|
| 学校端（勾课/生成/保存） | `/` | `PARTNER-1234` |
| 管理后台（自动跳转） | 同上，或 `/admin.html` | `ADMIN-0000` |

> ⚠️ 测试 PIN 请上线前改掉。学校 PIN 在后台管理；管理员 PIN 在 `app_admins` 表改。

## 文件

| 文件 | 作用 |
|------|------|
| `index.html` | 学校端 + 统一登入（读 catalog、勾课、生成架构表、保存、导出 PDF） |
| `admin.html` | 管理后台（帐号管理、开放板块、项目总览、导出各校 PDF） |
| `partner_full.sql` | **完整建置脚本**（从零建整套，幂等，一次跑完） |
| 其它 `*.sql` | 分步脚本（历史记录，已并入 partner_full.sql） |

## 部署

1. 上传本文件夹到 GitHub 仓库 `CICpartnerplan`
2. Settings → Pages → Deploy from a branch → `main` / `/root`
3. Supabase → SQL Editor → 跑 `partner_full.sql`

## 功能

**学校端**：统一登入 → 填学校/项目 → 选专业(dept)/版本(cohort) → 按板块勾课（显示代码/中英名/对接/学分/描述）→ 生成架构表（小计/专业合计/全项目合计/当天日期）→ 保存（可载入续编）→ 打印/导出 PDF（只出架构表）。

**管理后台**：新增/停用/删除合作校帐号；按专业设定每校**开放板块**白名单；项目总览；导出任一校的 PDF。

## 数据模型

- `catalog`（沿用排课系统，只读）：dept、version、block、block_credit、code、zh、en、credit、mapping、note…
- `partner_pins`：合作校帐号（pin、school_name、active、allowed_blocks）
- `partner_projects`：保存的项目（含勾选快照 payload）
- `app_admins`：管理员帐号
- 全走 SECURITY DEFINER 函数 + PIN 验证，匿名 key 只能经函数存取，各校隔离。

## 安全

- 与排课系统的 `authenticate` PIN **完全分开**；合作校只读得到 catalog，读不到排课数据。
- publishable key 为前端公开设计，实际门槛是各角色 PIN + 函数内验证。
