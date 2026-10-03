# 衣念 · 智能穿搭推荐（工程名 dapei-app）

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
| `BLOB_READ_WRITE_TOKEN` | **公开**图库：衣橱单品图（Vercel 面板连接 Blob 后自动注入） | 可选 |
| `PRIVATE_MODE_PASSWORD` | 私密模式门禁密码（建议 16 位以上随机串） | 私密模式必填 |
| `PRIVATE_BLOB_STORE_ID` | 🔒 **私密**图库：身体部位图/私密相册（access=Private 的独立 store） | 私密上传必填 |
| `PRIVATE_BLOB_READ_WRITE_TOKEN` | 仅当不用 OIDC 时才需要（连上项目后 Vercel 自动注入） | 可选 |
| `PRIVATE_USER_ID` | 私密数据 owner id（与衣橱侧 `u_demo_0001` 一致） | 可选 |

> LLM 三项缺省时自动回退规则文案，`WEATHER_API_KEY` 缺省时用 mock 天气 —— 都不会让接口报错。

### 🔒 私密图为什么需要「两个」Blob store

Vercel Blob 的 `access` 是 **store 级**属性：同一个 store 里没法一半 public 一半 private。
所以隐私相关的图（身体部位图、私密相册）必须单建一个 **access=Private** 的 store：

1. Vercel → 项目 → **Storage** → Create Storage → **Blob**
2. access 选 **Private**
3. **Advanced Options** → Environment Variable prefix 填 `PRIVATE_BLOB_`
4. Continue（自动 Connect to Project，无需手写任何token）→ **Redeploy**

私密图的访问链路：
`App` → `GET /api/private-image?pathname=private/xxx.jpg` + `Authorization: Bearer <token>`
→ 服务端验令牌 → 用服务端凭据 `get(blob, access:'private')` 取流 → 回给App。

> ⚠️ **私密 store 未配置时，私密图上传直接返回 503 拒绝**，不会静默落到公开 store ——
> 回退等于私密照片以公开 URL 落盘，这次改造就白做了。
> 数据库里存的是 blob 的 **pathname**，不是 URL；private-profile 的 photos 字段同理。

## 打包 App

```bash
cd app
# Web（前端静态产物）
flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<项目名>.vercel.app
# Android release（需先配好签名，见下）
flutter build apk --release
```

> ⚠️ `USE_MOCK` 现在**默认为 false**（真实模式）。想跑演示数据要显式
> `--dart-define=USE_MOCK=true`。原因：默认值 true 时，忘记加参数会得到一个
> 「看起来正常但所有写入只落本地、永不联库」的 App，且没有任何报错提示 ——
> 对涉及身体数据的私密功能尤其危险。

### 🔐 Android release 签名（不做就用不了 release 包）

release 构建**不再退回 debug 签名**：缺配置会直接中断构建并提示。
这是刻意为之——早前那句「Signing with the debug keys for now」让问题彻底隐形
（构建照过、装到手机上也没人发现，直到某天商店拒审或包被顶替）。

### 方式 A：本地出包

1. 生成 keystore（PKCS12 格式，**别提交进 git**）：
   ```bash
   cd app/android
   keytool -genkeypair -v -keystore yinian-release.p12 -storetype PKCS12 \
     -keyalg RSA -keysize 2048 -validity 10000 -alias yinian
   ```
2. 照着 `app/android/key.properties.example` 填好四项，存为 `app/android/key.properties`（同样不入库）
3. 正常 `flutter build apk --release`

> **改`build.gradle.kts` 时注意一个坑**：读 `key.properties` 不能写
> `java.util.Properties()`。Gradle Kotlin DSL 里 `java` 会解析成项目级的
> Java 插件扩展，`java.util` 就成了该扩展的属性访问，报
> `Unresolved reference 'util'`，连带 `getProperty`/`load` 全部失效，
> 整个 `assembleRelease` 编译中断。正确写法是文件顶部显式
> `import java.util.Properties` 然后用 `Properties()`，
> 且 import 必须放在 `plugins {}` 块**之前**，放后面同样编译失败。
> 这个错误只有真跑 Gradle 才暴露，`flutter analyze` 查不出来。

### 方式 B：GitHub Actions 出包（推荐，无需本地装Android SDK）

工作流 `.github/workflows/android-build.yml` 已配好，会自动还原签名材料、
跑 analyze + 测试、校验产物不是 debug 签名，最后发到 Releases。

**一次性配置**（仓库 Settings → Secrets and variables → Actions → New repository secret）：

| Secret 名 | 值 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | keystore 的 base64（见下方命令） |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_ALIAS` | `yinian` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |
| `API_BASE_URL` | `https://<项目名>.vercel.app` |

生成 base64（**注意 macOS/Linux 差异**，Linux 的 `-w0` 在 macOS 不可用）：

```bash
# Linux
base64 -w0 app/android/yinian-release.p12
# macOS
base64 -i app/android/yinian-release.p12 | tr -d '\n'
```

配好后有两个触发方式：
- **手动**：仓库页 Actions → Build Android APK → Run workflow
- **打 tag 自动触发并发布**：
  ```bash
  git tag v1.0.0 && git push origin v1.0.0
  ```
  产物自动进 Releases（含版本号的安装包），永久保留

> 私钥只存在于 GitHub 加密存储与runner 临时目录，任务结束即销毁，不入库。
> 缺任何签名 Secret 时构建会**明确失败**——这是刻意的，绝不产出 debug 签名的包。

> `*.p12` / `*.jks` / `key.properties` 都已在 `.gitignore` 里。
> **丢了 keystore 就没法再更新已发布的 App** —— 请单独备份到安全的地方。
> 存在 GitHub Secrets 里的是一份副本，本地这份丢了可以从 Secret 还原。

#### 校验签名为什么必须用 apksigner

工作流里校验产物用的是 `apksigner verify --print-certs`，不是更常见的
`keytool -printcert -jarfile`。原因很反直觉，值得记一笔：

本项目 `minSdk = 24`，此时 AGP **默认关闭 v1 签名**（`enableV1Signing=false`），
只生成 v2/v3 签名。两者的存放位置完全不同：

|方案 | 签名存放位置 | keytool 能读吗 |
|---|---|---|
| v1（JAR） | `META-INF/*.RSA` | 能 |
| v2 / v3 | ZIP 尾部的 `APK Sig Block 42` | **不能** |

`keytool -printcert -jarfile` 只认 v1。对 v2-only 的包，它输出
`Not a signed jar file`，**但退出码仍是 0** —— 于是 `set -e` 抓不到、
`grep CN=Yinian` 又匹配不到，表现为「签名校验莫名失败」，很像签名坏了，
其实是校验工具读不到。

`apksigner` 能识别全部方案，而且会真正验证签名完整性（`keytool` 只读证书，
不验签）。CI 上 `ubuntu-latest` 自带 Android SDK，直接可用。

> 本地校验同理：`$ANDROID_HOME/build-tools/*/apksigner verify --print-certs app-release.apk`

## 测试

```bash
npm test                # 服务端 24 项：token 鉴权 / 密码限速锁定 / 私密图路径白名单
cd app && flutter test  # 客户端 27 项：AI 结果解析 / 25 姿势完整性 / 肤色 prompt
```

两组测试都覆盖「改坏了不会立刻暴露」的关键逻辑：鉴权、暴力破解防护、
路径穿越防护、模型输出容错、姿势库完整性。改这几处前先跑一遍。


## 部署到 Vercel（推荐流程）

1. **推送本仓库到 GitHub**（见上一节命令），仓库地址：`https://github.com/Ezra-Maker-MAX/clothes`
2. [vercel.com](https://vercel.com) → **Add New → Project → Import** 该仓库，框架预设选 **Other**（API 是 Serverless Functions，零配置识别）
3. **Settings → Environment Variables** 逐条添加上表 `必填/建议` 的变量（Production + Preview 都勾上）
4. **Deploy**。部署完成后打开 `https://<项目名>.vercel.app/api/health` 验证数据库连通
5. 打包 App：`flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<项目名>.vercel.app`

> 数据库尚未建表时，本地执行 `node scripts/init-remote.mjs`（读 `.env`，幂等可重复跑）。

> 前端静态托管：Flutter Web 构建产物已入库 `public/`（Vercel Other 项目约定静态目录，与 `/api` 同域名自动共存，前端请求零 CORS）。更新前端：本地执行 `flutter build web --release --dart-define=USE_MOCK=false --dart-define=API_BASE_URL=https://<项目名>.vercel.app`，然后把 `app/build/web/*` 覆盖到 `public/` 提交推送即可。

## 私密模式（🍑 隐蔽入口）

入口**不在UI 上显式出现**：它在「设置」页最底部的隐私说明文字末尾，是一枚
普通的 🍑 表情。**2 秒内连点 5 次**才触发，过程中零反馈。

- 密码只存在环境变量 `PRIVATE_MODE_PASSWORD`，客户端安装包与本地存储均无密码
- 校验通过 → 服务端下发 HMAC token（默认 7 天）→ 围度/肤色/部位图接口凭 token 读写
- 本地只记「解锁时间戳」，24 小时内重启 App 免重复输入；不记密码
- 连续输错 5 次按 IP 锁定 15 分钟
- 「退出私密模式」立即切回日常主题并清空时间戳与 token

> 改密码（换环境变量值）= 所有旧 token **立刻全部失效**。
> 客户端解锁记忆 24h 与服务端 token 7 天是两套独立时限，当前实现不会错配；
> 但若将来加「自动续期」，务必先统一这两个时长。

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

- `USE_MOCK` 由构建参数控制：**默认 false（真实模式）**；想跑演示数据显式加 `--dart-define=USE_MOCK=true`
- 真实模式下天气卡、排重（避开昨日穿过）、"换一套"轮换、"就穿这套"落库全部走 `/api`
