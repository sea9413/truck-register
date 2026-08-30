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


-- ===== 第 6 块：验收（跑完上面几块后执行，看结果对不对）=====
-- 列数应为 22（15 个基础列 + v1.2~v1.6 陆续新增的 7 个列）
select count(*) as column_count
from information_schema.columns
where table_name = 'records';

-- 策略数应为 4（SELECT / INSERT / UPDATE / DELETE）
select policyname, cmd
from pg_policies
where tablename = 'records'
order by cmd;
