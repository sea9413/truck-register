-- 在 Supabase SQL Editor 里执行这段代码
-- 创建装货登记表

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
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 允许匿名读写（所有人都能用，不需要登录）
ALTER TABLE records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous read" ON records
  FOR SELECT USING (true);

CREATE POLICY "Allow anonymous insert" ON records
  FOR INSERT WITH CHECK (true);
