-- ============================================================
-- 「搭配测试」App · Turso (LibSQL/SQLite) 表结构 Schema v0.1
-- 设计原则：
--   1) 图片一律存 URL（Vercel Blob / Cloudinary），Turso 只存指针
--   2) 排重靠 wardrobe_items.last_worn_at 冗余字段，避免每次扫历史表
--   3) 每日推荐缓存 UNIQUE(user_id, recommend_date, occasion)，
--      同人同日同场合只生成一次，"换一套"走 refresh 覆盖，不烧 API 额度
--   4) 灵活属性（三围、风格偏好、天气快照、推荐明细）用 JSON 文本列，
--      SQLite 无原生 JSON 类型，TEXT + json_extract 足够
-- ============================================================

-- ------------------------------------------------------------
-- 1. users 用户信息 + 用户画像（三围/肤色/脸型/风格偏好）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                TEXT PRIMARY KEY,            -- UUID，应用层生成
  nickname          TEXT NOT NULL,               -- 昵称（如"尊贵的公主"）
  avatar_url        TEXT,                        -- 头像 URL（Blob/CDN）
  phone             TEXT UNIQUE,                 -- 手机号，预留登录
  height_cm         REAL,                        -- 身高
  weight_kg         REAL,                        -- 体重
  bust_cm           REAL,                        -- 胸围（三围之一）
  waist_cm          REAL,                        -- 腰围
  hip_cm            REAL,                        -- 臀围
  skin_tone         TEXT,                        -- 肤色: fair/warm/neutral/deep
  face_shape        TEXT,                        -- 脸型: oval/round/square/heart/long
  style_preferences TEXT,                        -- 风格偏好 JSON 数组，如 ["通勤","法式","辣妹"]
  color_preferences TEXT,                        -- 偏好色系 JSON，如 {"love":["muted"],"avoid":["neon"]}
  city              TEXT,                        -- 常驻城市，天气 API 主键之一
  latitude          REAL,                        -- 定位纬度（可选，优先于 city）
  longitude         REAL,                        -- 定位经度
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ------------------------------------------------------------
-- 2. wardrobe_items 虚拟衣橱单品
--    字段专门为"情景引擎"服务：warmth_level 匹配体感温度，
--    formality 匹配场合，color_family 匹配莫兰迪配色，pattern 支撑文案细节（波点等）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS wardrobe_items (
  id            TEXT PRIMARY KEY,                -- UUID
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,                   -- 单品名："斜扣浅蓝牛仔裤"
  image_url     TEXT NOT NULL,                   -- 主图 URL（必填，Blob/Cloudinary）
  thumbnail_url TEXT,                            -- 缩略图 URL（列表页提速）
  category      TEXT NOT NULL CHECK (category IN (
                  'tops','bottoms','dresses','outerwear',
                  'shoes','bags','accessories')), -- 大分类
  sub_category  TEXT,                            -- 子分类: shirt/t-shirt/jeans/heel/...
  color_name    TEXT,                            -- 显示色名："米色"
  color_hex     TEXT,                            -- 主色 HEX："#E8E0D0"
  color_family  TEXT,                            -- 色系: neutral/muted/warm/cool/dark/bright
  pattern       TEXT,                            -- 图案: plain/polka-dot/stripes/plaid（文案素材）
  season        TEXT,                            -- 适用季节 JSON，如 ["spring","autumn"]
  warmth_level  INTEGER NOT NULL DEFAULT 2 CHECK (warmth_level BETWEEN 1 AND 5),
                -- 厚度冷暖 1~5：1=清凉(吊带/凉鞋) 5=厚重(羽绒/雪地靴)
  formality     INTEGER NOT NULL DEFAULT 2 CHECK (formality BETWEEN 1 AND 5),
                -- 正式度 1~5：1=居家 2=日常 3=通勤 4=约会 5=面试/正装
  brand         TEXT,
  price         NUMERIC,                         -- 购入价格（元），惰性迁移列（ensureSchema 自动 ADD）
  image_urls    TEXT,                            -- 多图 JSON 数组字符串，惰性迁移列；主图仍为 image_url
  pinned        INTEGER NOT NULL DEFAULT 0,      -- 1 = 置顶，惰性迁移列（列表排序优先）
  source        TEXT NOT NULL DEFAULT 'upload',  -- 来源: upload/ai_generated/import
  tags          TEXT,                            -- 自由标签 JSON
  wear_count    INTEGER NOT NULL DEFAULT 0,      -- 累计穿着次数 → 首页"未穿单品"统计
  last_worn_at  TEXT,                            -- 最后穿着日期 YYYY-MM-DD → 排重核心字段
  is_favorite   INTEGER NOT NULL DEFAULT 0,      -- 心动单品
  status        TEXT NOT NULL DEFAULT 'active',  -- active/archived（软删）
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- 衣橱列表高频查询：按人 + 分类拉取
CREATE INDEX IF NOT EXISTS idx_items_user_category ON wardrobe_items(user_id, category);
-- 排重/未穿单品：按最后穿着时间排序
CREATE INDEX IF NOT EXISTS idx_items_last_worn ON wardrobe_items(user_id, last_worn_at);

-- 动态分类（衣橱 tab 展示层；item.category 存分类 id，经 engine_key 映射推荐引擎）
-- ⚠️ 线上库由 api/lib/db.ts ensureSchema() 惰性创建（幂等），此定义用于新库初始化与文档
CREATE TABLE IF NOT EXISTS categories (
  id          TEXT PRIMARY KEY,                -- 内置行 id = 引擎 key（tops/bottoms/...）
  user_id     TEXT NOT NULL,
  name        TEXT NOT NULL,
  engine_key  TEXT NOT NULL,                   -- 映射到推荐引擎的适配类别
  sort_order  INTEGER NOT NULL DEFAULT 0,
  is_builtin  INTEGER NOT NULL DEFAULT 0,      -- 内置分类不可删除
  created_at  TEXT DEFAULT (datetime('now'))
);

-- ------------------------------------------------------------
-- 3. outfit_history 穿搭历史（"本月搭配"统计 + 排重数据源）
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS outfit_history (
  id                   TEXT PRIMARY KEY,
  user_id              TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  worn_date            TEXT NOT NULL,           -- 穿着日期 YYYY-MM-DD
  item_ids             TEXT NOT NULL,           -- 当日单品 ID JSON 数组 ["id1","id2","id3"]
  outfit_name          TEXT,                    -- 搭配名（可选）："奶油波点通勤日"
  occasion             TEXT NOT NULL,           -- 场合: commute/date/interview/casual/party
  weather_snapshot     TEXT,                    -- 天气快照 JSON：{"tempC":24,"feelsLike":25,"condition":"多云"}
  makeup_recommendation TEXT,                   -- 妆容方案（当日实际采用）
  reason               TEXT,                    -- 推荐理由存档（情绪价值文案）
  rating               INTEGER CHECK (rating BETWEEN 1 AND 5),  -- 满意度
  feedback             TEXT,                    -- 一句话感受
  notes                TEXT,                    -- 用户手写穿搭日记（详情页可编辑保存）
  source               TEXT NOT NULL DEFAULT 'recommended',  -- recommended/manual
  created_at           TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_history_user_date ON outfit_history(user_id, worn_date DESC);
CREATE INDEX IF NOT EXISTS idx_history_user_occasion ON outfit_history(user_id, occasion);

-- ------------------------------------------------------------
-- 4. daily_recommendations 每日推荐缓存（核心省钱表）
--    UNIQUE 约束：同一用户同一天同一场合只缓存一条，
--    前端刷新直接命中缓存，"换一套"用 refresh 覆盖写，不重复调 AI
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_recommendations (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  recommend_date    TEXT NOT NULL,               -- YYYY-MM-DD
  occasion          TEXT NOT NULL,               -- 场合标签
  weather_snapshot  TEXT,                        -- 当日天气 JSON（顺带缓存天气 API 结果）
  outfit_json       TEXT NOT NULL,               -- 完整推荐 JSON：单品明细+图片URL+妆容+理由
  item_ids          TEXT,                        -- 推荐单品 ID JSON 数组（快速排重比对）
  reason            TEXT,                        -- 匹配理由文案（详情页直读）
  makeup            TEXT,                        -- 妆容推荐
  alt_outfits_json  TEXT,                        -- 备选搭配 JSON 数组（"换一套"优先从这里取，0 成本）
  status            TEXT NOT NULL DEFAULT 'pending',
                    -- pending=已生成未展示 / shown=已展示 / accepted=就穿这套
  is_accepted       INTEGER NOT NULL DEFAULT 0,  -- 用户点了"就穿这套"
  swap_count        INTEGER NOT NULL DEFAULT 0,  -- "换一套"次数（观察选择困难度）
  model             TEXT DEFAULT 'rule-based',   -- 生成来源: rule-based/llm-xxx
  expires_at        TEXT,                        -- 缓存过期时间（次日 05:00，跨夜兜底）
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(user_id, recommend_date, occasion)
);

CREATE INDEX IF NOT EXISTS idx_rec_user_date ON daily_recommendations(user_id, recommend_date DESC);
