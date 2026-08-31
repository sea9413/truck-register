-- ============================================================
-- 装货登记 · 数据库脚本
--
-- 用法一：整段复制，在 Supabase SQL Editor 里执行一次。
-- 用法二：如果整段跑报 "Backend error"，就按下面的【第 1 块】
--        【第 2 块】... 一块一块单独执行，哪块报错就单独重跑哪块。
--
-- 所有语句都是幂等的：重复执行不会报错，也不会影响已有数据。
-- 急着修功能的话，最少只要跑【第 2 块】和【第 5 块】。
-- ============================================================


-- ===== 第 1 块：建表（新库用；老库会安全跳过，不会重建）=====
CREATE TABLE IF NOT EXISTS records (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  date TEXT,
  plate_main TEXT NOT NULL,
  plate_trailer TEXT,
  name TEXT,
  phone TEXT,
  id_card TEXT,
  from_location TEXT,
  to_location TEXT,
  goods TEXT,
  freight TEXT,
  weight TEXT,
  weigh_fee TEXT,
  notice TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- v1.2+ 运输类型：送货 / 退货 / 不统计
  delivery_type TEXT DEFAULT '送货',
  -- v1.3+ 备注
  note TEXT,
  -- v1.4+ 运费是否已结清
  is_paid BOOLEAN DEFAULT false,
  -- v1.5+ 被修改过的字段列表与次数（详情页标红用）
  modified_fields JSONB DEFAULT '[]'::jsonb,
  modified_count INTEGER DEFAULT 0,
  -- v1.6+ 软删除（回收站）
  deleted BOOLEAN DEFAULT false,
  deleted_at TIMESTAMP WITH TIME ZONE
);


-- ===== 第 2 块：老表补列（已存在则跳过，不会动已有数据）=====
ALTER TABLE records ADD COLUMN IF NOT EXISTS delivery_type TEXT DEFAULT '送货';
ALTER TABLE records ADD COLUMN IF NOT EXISTS note TEXT;
ALTER TABLE records ADD COLUMN IF NOT EXISTS is_paid BOOLEAN DEFAULT false;
ALTER TABLE records ADD COLUMN IF NOT EXISTS modified_fields JSONB DEFAULT '[]'::jsonb;
ALTER TABLE records ADD COLUMN IF NOT EXISTS modified_count INTEGER DEFAULT 0;
ALTER TABLE records ADD COLUMN IF NOT EXISTS deleted BOOLEAN DEFAULT false;
ALTER TABLE records ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP WITH TIME ZONE;


-- ===== 第 3 块：老数据补默认值（避免 NULL 导致筛选/统计失效）=====
UPDATE records SET delivery_type  = '送货'        WHERE delivery_type  IS NULL;
UPDATE records SET is_paid        = false         WHERE is_paid        IS NULL;
UPDATE records SET modified_count = 0             WHERE modified_count IS NULL;
UPDATE records SET deleted        = false         WHERE deleted        IS NULL;
UPDATE records SET modified_fields = '[]'::jsonb  WHERE modified_fields IS NULL;


-- ===== 第 4 块：索引（加快列表加载和筛选）=====
CREATE INDEX IF NOT EXISTS idx_records_created_at   ON records (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_records_date         ON records (date);
CREATE INDEX IF NOT EXISTS idx_records_deleted      ON records (deleted);
CREATE INDEX IF NOT EXISTS idx_records_plate_main   ON records (plate_main);


-- ===== 第 5 块：权限策略（最关键的一块）=====
-- 原来的脚本开了 RLS 却只给了 SELECT + INSERT，导致
--   修改记录 / 删除 / 回收站恢复 / 清空全部
-- 四个功能全部被数据库静默拒绝。
-- 这里用「先删后建」保证幂等，重复执行不会报「策略已存在」。
ALTER TABLE records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow anonymous read" ON records;
CREATE POLICY "Allow anonymous read" ON records
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Allow anonymous insert" ON records;
CREATE POLICY "Allow anonymous insert" ON records
  FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anonymous update" ON records;
CREATE POLICY "Allow anonymous update" ON records
  FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow anonymous delete" ON records;
CREATE POLICY "Allow anonymous delete" ON records
  FOR DELETE USING (true);


-- ===== 第 6 块：v1.7.2 操作人 + 操作日志 + 识别样本（新增表和列）=====

-- 6.1 records 补「操作人」列：记录这条是谁录入的 / 谁最后改的
ALTER TABLE records ADD COLUMN IF NOT EXISTS operator TEXT;

-- 6.2 操作日志表：谁、什么时候、对哪条记录、做了什么
CREATE TABLE IF NOT EXISTS operation_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  operator TEXT,                 -- 操作人姓名（首次进入时填，存在浏览器本地）
  action TEXT,                   -- create / update / delete / restore / paid / clear
  record_id UUID,                -- 关联的记录 id（清空全部时为 NULL）
  record_plate TEXT,             -- 冗余存车牌，日志里一眼看出是哪台车
  detail TEXT                    -- 变更详情，如「运费: 100→200；姓名: 张三→李四」
);

-- 6.3 识别失败样本表：识别不准的原文攒在这里，攒够一批再针对性补规则
CREATE TABLE IF NOT EXISTS recognize_failures (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  operator TEXT,
  raw_text TEXT,                 -- 用户粘贴的原文
  reason TEXT,                   -- all_empty(整段没识别出) / missing_key(关键字段缺失)
  missing_fields TEXT,           -- 没识别出哪些字段，如「姓名,手机」
  parsed_json TEXT,              -- 当时的识别结果，便于事后分析
  resolved BOOLEAN DEFAULT false -- 是否已据此优化过规则
);

-- 6.4 索引
CREATE INDEX IF NOT EXISTS idx_logs_created_at ON operation_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_record_id  ON operation_logs (record_id);
CREATE INDEX IF NOT EXISTS idx_fail_created_at ON recognize_failures (created_at DESC);

-- 6.5 权限策略（和 records 一样：anon 可读可写，否则前端写不进去）
ALTER TABLE operation_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow anonymous read logs" ON operation_logs;
CREATE POLICY "Allow anonymous read logs" ON operation_logs FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow anonymous insert logs" ON operation_logs;
CREATE POLICY "Allow anonymous insert logs" ON operation_logs FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous update logs" ON operation_logs;
CREATE POLICY "Allow anonymous update logs" ON operation_logs FOR UPDATE USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous delete logs" ON operation_logs;
CREATE POLICY "Allow anonymous delete logs" ON operation_logs FOR DELETE USING (true);

ALTER TABLE recognize_failures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow anonymous read failures" ON recognize_failures;
CREATE POLICY "Allow anonymous read failures" ON recognize_failures FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow anonymous insert failures" ON recognize_failures;
CREATE POLICY "Allow anonymous insert failures" ON recognize_failures FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous update failures" ON recognize_failures;
CREATE POLICY "Allow anonymous update failures" ON recognize_failures FOR UPDATE USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous delete failures" ON recognize_failures;
CREATE POLICY "Allow anonymous delete failures" ON recognize_failures FOR DELETE USING (true);


-- ===== 第 7 块：v1.8.0 地点名称库（司机原始写法 → 标准名）=====

-- 每行是一条「别名 → 标准名」映射。同一个标准名可以有多行别名。
-- 例：standard_name='茂名沉香工地' 对应三行 alias：
--     '茂名沉香工地' / '沉香工地' / '电白沉香工地'
CREATE TABLE IF NOT EXISTS location_aliases (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  standard_name TEXT NOT NULL,   -- 标准名：登记、统计、筛选统一用这个
  alias TEXT NOT NULL,           -- 司机可能写出来的原始写法
  sort_order INTEGER DEFAULT 0,  -- 排序用，大的在前
  UNIQUE (alias, standard_name)  -- 同一标准名下别名不重复
);

CREATE INDEX IF NOT EXISTS idx_loc_alias    ON location_aliases (alias);
CREATE INDEX IF NOT EXISTS idx_loc_standard ON location_aliases (standard_name);

-- 权限策略（和 records 一致：anon 可读可写）
ALTER TABLE location_aliases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow anonymous read loc" ON location_aliases;
CREATE POLICY "Allow anonymous read loc" ON location_aliases FOR SELECT USING (true);
DROP POLICY IF EXISTS "Allow anonymous insert loc" ON location_aliases;
CREATE POLICY "Allow anonymous insert loc" ON location_aliases FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous update loc" ON location_aliases;
CREATE POLICY "Allow anonymous update loc" ON location_aliases FOR UPDATE USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "Allow anonymous delete loc" ON location_aliases;
CREATE POLICY "Allow anonymous delete loc" ON location_aliases FOR DELETE USING (true);

-- 预置一批常用地点（根据 2026-09-01 提供的 23 条真实司机信息整理）
-- 已确认：电白沉香工地 = 茂名沉香工地；茂名/茂南/国基仓库 同一个；
--         博贺展示中心 = 茂名展示中心 = 茂名博贺展示中心
INSERT INTO location_aliases (standard_name, alias, sort_order) VALUES
  ('茂名沉香工地',     '茂名沉香工地',     100),
  ('茂名沉香工地',     '沉香工地',         100),
  ('茂名沉香工地',     '电白沉香工地',     100),
  ('茂南消防基地',     '茂南消防基地',      90),
  ('茂南消防基地',     '消防基地',          90),
  ('茂名博贺展示中心', '茂名博贺展示中心',   80),
  ('茂名博贺展示中心', '博贺展示中心',      80),
  ('茂名博贺展示中心', '茂名展示中心',      80),
  ('茂名仓库',         '茂名仓库',          70),
  ('茂名仓库',         '茂南仓库',          70),
  ('茂名仓库',         '茂名国基仓库',      70),
  ('茂南国民市场',     '茂南国民市场',      60),
  ('茂南国民市场',     '国民市场',          60),
  ('广州胜华',         '广州胜华',          50),
  ('开平鹏峰',         '开平鹏峰',          50),
  ('马踏工地',         '马踏工地',          40),
  ('茂南图书馆',       '茂南图书馆',        40),
  ('茂南石油学院',     '茂南石油学院',      30),
  ('广东长远建材',     '广东长远建材',      30),
  ('茂南亿宝工地',     '茂南亿宝工地',      30)
ON CONFLICT (alias, standard_name) DO NOTHING;


-- ===== 第 8 块：验收（跑完上面几块后执行，看结果对不对）=====
-- records 列数应为 23（原 22 列 + operator）
select count(*) as records_column_count
from information_schema.columns
where table_name = 'records';

-- 应有 4 张表：records / operation_logs / recognize_failures / location_aliases
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('records','operation_logs','recognize_failures','location_aliases')
order by table_name;

-- 四张表各自的策略数都应为 4（SELECT / INSERT / UPDATE / DELETE）
select tablename, count(*) as policy_count
from pg_policies
where tablename in ('records','operation_logs','recognize_failures','location_aliases')
group by tablename
order by tablename;

-- 地点库应有 20 条映射、13 个标准名
select count(*) as 映射条数, count(distinct standard_name) as 标准名个数
from location_aliases;
