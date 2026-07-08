# Partner Course Planner · 校校合作课程规划系统

合作校老师从课程库勾选课程，自动生成分专业、分模块的**课程架构表**（专业中英名、学年课纲、课程中英名、学分、总课数、总学分）。

线上地址（GitHub Pages）：
<https://ali-che.github.io/CICpartnerplan/>

---

## 文件说明

| 文件 | 作用 |
|------|------|
| `index.html` | 前端页面（**目前是 DEMO，用假数据**，可直接打开操作） |
| `schema.sql` | Supabase 建表 + 权限脚本（`projects`、`project_courses`、RLS） |
| `README.md` | 本说明 |

## 操作流程

填资料 → 选学年 → 选专业 → 勾课 → 生成课程架构表 → 打印 / 导出 PDF

- 学年、专业清单**从数据库读出**（DEMO 版用内建假数据模拟）
- 勾选可跨专业累积到同一份架构表
- 切换学年会重设勾选（一个项目只属于一个学年课纲）

## 部署到 GitHub Pages

1. 把本文件夹的文件上传到仓库 `CICpartnerplan`
2. 仓库 **Settings → Pages** → Source 选 `main` 分支、根目录 `/`
3. 稍等 1 分钟，访问 <https://ali-che.github.io/CICpartnerplan/>

## 路线图（DEMO → 成品）

- [x] 前端界面与交互逻辑（勾课、分组、小计、生成架构表）
- [ ] 接上 Supabase：假数据换真课程库（读现有排课系统的 courses / 专业 / 学年）
- [ ] 加登入：每校一个帐号，只看得到自己的项目（RLS 已在 `schema.sql` 写好）
- [ ] 后台：帐号管理 + 课程库维护
- [ ] 导出美化：Excel（SheetJS）

> DEMO 的画面与逻辑即为成品前端，接数据库时不需重做，只把「假数据」换成「真数据 + 登入」。

## 数据模型要点

- `courses`（沿用现有排课系统的课程库，只读）：专业中英名、`academic_year`、大标题、课程中英名、学分
- `projects`：合作学校名、项目名、适用学年
- `project_courses`：勾选纪录（一门课在一个项目里只勾一次）
- 学年、专业不另建表，直接从 `courses` `distinct` 出来

详见 `schema.sql`。
