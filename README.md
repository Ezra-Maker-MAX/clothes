# 搭配测试 · dapei-app

智能穿搭推荐 App（面向女性用户）——懂她、宠她、有分寸地撩她。
根据**天气、场合、个人衣橱、穿搭历史**，一站式给出服装 + 鞋 + 妆容方案和推荐理由。

> 本仓库已完成 **第一~三阶段**：表结构 Schema + Vercel API 层 + Flutter 全端 UI + 本地联调（真实数据流跑通）。
> 第三阶段已接入和风天气、实现"换一套 / 就穿这套"真实流转，本地可用 `scripts/dev-server.ts` 单端口预览。

## 目录结构

```
dapei-app/
├── db/
│   ├── schema.sql            # ★ Turso 表结构（users / wardrobe_items / outfit_history / daily_recommendations）
│   └── seed.sql              # 演示数据（可选，验证排重用）
├── api/                      # Vercel Serverless Functions (TypeScript)
│   ├── health.ts             # ★ 测试接口：浏览器打开即验证数据库连通性
│   ├── wardrobe.ts           # 衣橱 CRUD（GET 列表 / POST 新增 / DELETE 软删）
│   ├── recommend.ts          # 每日推荐（缓存优先 → 情景引擎 → UPSERT；refresh=1 即"换一套"）
│   ├── history.ts            # 穿搭历史（事务：写历史 + 更新 wear_count/last_worn_at）
│   ├── upload.ts             # 图片上传（Vercel Blob，Turso 只存 URL）
│   └── lib/
│       ├── db.ts             # Turso 客户端（环境变量缺失自动降级本地 SQLite）
│       ├── engine.ts         # 情景引擎 v0.2：排重 + 厚度/正式度匹配 + Top-3 轮换（"换一套"）
│       ├── weather.ts        # 和风天气接入（缺 KEY/失败自动降级 mock）
│       ├── llm.ts            # 推荐理由 LLM 润色（失败自动回退规则文案）
│       ├── http.ts           # 响应统一结构 + CORS
│       └── types.ts          # 前后端共享数据契约
├── docs/
│   ├── 01-表结构设计.md       # 字段设计决策、索引、省钱缓存结构
│   ├── 02-部署与CI指南.md     # Vercel Git 集成 + Actions 打 APK + 跑通验证步骤
│   └── 03-图片存储方案.md     # Vercel Blob vs Cloudinary 对比 + 抠图挂载点
├── .github/workflows/
│   ├── android-build.yml     # push tag / 手动触发 → Flutter Release APK
│   └── vercel-deploy.yml     # 可选：Actions CLI 部署（默认用 Vercel Git 集成）
├── app/                      # （第二阶段）Flutter 前端，规划：
│   ├── lib/pages/            #   home / wardrobe / outfit / history 四页
│   ├── lib/services/         #   api_client.dart / weather_service.dart
│   └── pubspec.yaml
├── scripts/                  # 本地联调工具（开发期替代 Vercel）
│   ├── dev-server.ts        # 单端口托管 Web + 挂载 /api
│   ├── seed-local.mjs       # 用本地 SQLite 模拟 Turso 并灌演示数据
│   └── init-remote.mjs      # 幂等初始化远程 Turso（建表 + 演示数据）
├── vercel.json / package.json / tsconfig.json
└── .env.example              # ★ 环境变量清单（TURSO_URL / TURSO_AUTH_TOKEN / ...）
```

## 四条开发策略的落实对照

| 你的策略 | 本仓库落点 |
|---|---|
| 1. 先出表结构 | `db/schema.sql` 四张表 + 设计文档 `docs/01`（排重冗余字段、缓存 UNIQUE 约束） |
| 2. push 自动部署 + Actions 打包 | Vercel Git 集成文档 `docs/02`；`android-build.yml` 打 tag 即出 APK |
| 3. 图片只存 URL | `/api/upload` 接 Vercel Blob，方案对比与退路见 `docs/03` |
| 4. 先跑通后端再画 UI | `/api/health` 浏览器打开即返回数据（未配环境变量也有 mock 响应，永不白屏） |

## 快速开始（跑通后端）

```bash
# 1. 安装依赖
pnpm install

# 2. 建库（首次）
turso db create dapei
turso db shell dapei < db/schema.sql
turso db show dapei --url          # → TURSO_URL
turso db tokens create dapei       # → TURSO_AUTH_TOKEN

# 3. 本地配置（从模板复制后填入上面两个值）
cp .env.example .env

# 4. 启动并验证
vercel dev
# 浏览器打开 http://localhost:3000/api/health
```

部署到线上见 `docs/02-部署与CI指南.md`（GitHub 绑 Vercel 后，push 即部署）。

## 本地联调（开发期，无需部署 Vercel）

沙箱/本机无法一键部署 Vercel 时，用 `scripts/dev-server.ts` 把 `api/*.ts` 挂成真实 HTTP 接口，
并顺带托管 Flutter Web 产物，**单端口即可预览真实数据流**：

```bash
pnpm install
# 用本地 SQLite 文件模拟 Turso（无需 Turso 账号）
LOCAL_DB=./local.db npm run seed
# 起服务（默认 3001，同时托管 Web + /api）
PORT=3001 LOCAL_DB=./local.db npm run local
# 浏览器打开 http://localhost:3001 即见真实推荐 / 换一套 / 就穿这套
```

前端切真实数据：构建时加 `--dart-define=USE_MOCK=false --dart-define=API_BASE_URL=http://localhost:3001`。
联调用的本地库与线上 Turso **表结构完全一致**（同一份 `db/schema.sql`），逻辑零差异；
部署到 Vercel 时只需把 `LOCAL_DB` 换成 `TURSO_URL + TURSO_AUTH_TOKEN` 即可。

## 环境变量（⚠️ 涉及凭证，只进 Vercel/本地 .env，不进 git）

| 变量 | 用途 | 必填 |
|---|---|---|
| `TURSO_URL` | Turso 数据库地址（`libsql://...`） | ✅ |
| `TURSO_AUTH_TOKEN` | Turso 访问令牌 | ✅ |
| `LLM_API_KEY` | 推荐理由 LLM 润色（OpenAI 兼容接口） | 建议 |
| `LLM_BASE_URL` | LLM 接口地址（如 `https://apihub.agnes-ai.com/v1`） | 建议 |
| `LLM_MODEL` | LLM 模型名（如 `agnes-2.5-flash`） | 建议 |
| `WEATHER_API_KEY` | 和风天气 KEY（缺省自动用 mock 天气，不影响主流程） | 可选 |
| `BLOB_READ_WRITE_TOKEN` | 图片上传（Vercel 面板连接 Blob 后自动注入） | 可选 |

> LLM 三项缺省时自动回退规则文案，`WEATHER_API_KEY` 缺省时用 mock 天气 —— 都不会让接口报错。

## 部署到 Vercel（推荐流程）

1. **推送本仓库到 GitHub**（见上一节命令），仓库地址：`https://github.com/Ezra-Maker-MAX/clothes`
2. [vercel.com](https://vercel.com) → **Add New → Project → Import** 该仓库，框架预设选 **Other**（API 是 Serverless Functions，零配置识别）
3. **Settings → Environment Variables** 逐条添加上表 `必填/建议` 的变量（Production + Preview 都勾上）
4. **Deploy**。部署完成后打开 `https://<项目名>.vercel.app/api/health` 验证数据库连通
5. 打包 App：`flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<项目名>.vercel.app`

> 数据库尚未建表时，本地执行 `node scripts/init-remote.mjs`（读 `.env`，幂等可重复跑）。

## 路线图

- [x] **第一阶段**：表结构 + 目录结构 + Actions 配置思路
- [x] **第二阶段**：Flutter 全端 UI（首页 + 衣橱 + 搭配 + 穿搭日记月历）+ 数据模拟 + Web 构建
- [x] **第三阶段**：接入和风天气 API + 本地联调 server，前后端真实数据流（换一套 / 就穿这套 / 排重）全部跑通验证

## Flutter 端（app/）

```bash
cd app
flutter pub get
flutter run -d chrome            # 本地开发
flutter build web --release      # Web 端构建 → build/web（Vercel 部署静态产物）
```

- `USE_MOCK` 由构建参数控制：默认 true（本地模拟数据）；联调/上线加 `--dart-define=USE_MOCK=false` 走真实接口
- 真实模式下天气卡、排重（避开昨日穿过）、"换一套"轮换、"就穿这套"落库全部走 `/api`
