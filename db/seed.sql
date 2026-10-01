-- ============================================================
-- 种子数据：仅在本地/开发库执行，用于跑通测试接口
-- 生产环境通过 App 上传衣橱后自动写入
-- ============================================================

-- 演示用户
INSERT INTO users (id, nickname, city, style_preferences)
VALUES ('u_demo_0001', '尊贵的公主', '上海', '["通勤","法式","温柔风"]')
ON CONFLICT(id) DO NOTHING;

-- 衣橱单品：每类多件、不同厚度/正式度/色系，保证「换一套」能换出差异、
-- 「排重」能明显避开历史穿过的件（历史只穿其中 top_01/bottom_01/shoe_01）
INSERT INTO wardrobe_items (id, user_id, name, image_url, category, sub_category,
                            color_name, color_hex, color_family, pattern,
                            warmth_level, formality)
VALUES
  -- 上衣 (4)
  ('w_demo_top_01', 'u_demo_0001', '白色波点衬衫', 'https://placehold.co/400x533?text=Top1',
   'tops', 'shirt', '白色', '#FFFFFF', 'neutral', 'polka-dot', 2, 3),
  ('w_demo_top_02', 'u_demo_0001', '燕麦色针织开衫', 'https://placehold.co/400x533?text=Top2',
   'tops', 'knit', '燕麦色', '#E8DCC8', 'warm', 'plain', 3, 2),
  ('w_demo_top_03', 'u_demo_0001', '雾霾蓝缎面衬衫', 'https://placehold.co/400x533?text=Top3',
   'tops', 'shirt', '雾霾蓝', '#9DB4C0', 'cool', 'plain', 2, 4),
  ('w_demo_top_04', 'u_demo_0001', '条纹长袖T', 'https://placehold.co/400x533?text=Top4',
   'tops', 'tee', '条纹', '#D8D2C8', 'neutral', 'striped', 2, 1),
  -- 裤装 (3)
  ('w_demo_bottom_01', 'u_demo_0001', '斜扣浅蓝牛仔裤', 'https://placehold.co/400x533?text=Bot1',
   'bottoms', 'jeans', '浅蓝', '#A8C4D9', 'cool', 'plain', 2, 2),
  ('w_demo_bottom_02', 'u_demo_0001', '白色阔腿西装裤', 'https://placehold.co/400x533?text=Bot2',
   'bottoms', 'trousers', '白色', '#F2F0EC', 'neutral', 'plain', 2, 4),
  ('w_demo_bottom_03', 'u_demo_0001', '米色烟管裤', 'https://placehold.co/400x533?text=Bot3',
   'bottoms', 'trousers', '米色', '#E8E0D0', 'warm', 'plain', 2, 3),
  -- 鞋子 (3)
  ('w_demo_shoe_01', 'u_demo_0001', '米色尖头凉鞋', 'https://placehold.co/400x533?text=Shoe1',
   'shoes', 'sandal', '米色', '#E8E0D0', 'warm', 'plain', 1, 3),
  ('w_demo_shoe_02', 'u_demo_0001', '裸色平底穆勒鞋', 'https://placehold.co/400x533?text=Shoe2',
   'shoes', 'mule', '裸色', '#E2C9BE', 'warm', 'plain', 2, 3),
  ('w_demo_shoe_03', 'u_demo_0001', '白色小皮鞋', 'https://placehold.co/400x533?text=Shoe3',
   'shoes', 'flat', '白色', '#F2F0EC', 'neutral', 'plain', 2, 3)
ON CONFLICT(id) DO NOTHING;

-- 演示历史（昨天穿过 top_01/bottom_01/shoe_01 → 今天推荐必须避开，验证排重）
INSERT INTO outfit_history (id, user_id, worn_date, item_ids, occasion, reason, source)
VALUES ('h_demo_0001', 'u_demo_0001',
        date('now', '-1 day'),
        '["w_demo_top_01","w_demo_bottom_01","w_demo_shoe_01"]',
        'commute', '经典通勤组合，今天得换换口味。', 'manual')
ON CONFLICT(id) DO NOTHING;
