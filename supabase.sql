-- SQL Script for Supabase Table Creation

-- Create Expenses table
CREATE TABLE IF NOT EXISTS expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  amount FLOAT NOT NULL,
  category TEXT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  notes TEXT
);

-- Create Settlements table
CREATE TABLE IF NOT EXISTS settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  amount FLOAT NOT NULL,
  settled_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  settled_by TEXT NOT NULL
);

-- Enable Row Level Security (RLS)
-- For an MVP we might keep it simple, but here is a basic setup:
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;

-- Allow public access for now as per "MVP/No Login" requirement (security depends on Anon Key)
CREATE POLICY "Public Read/Write Access" ON expenses FOR ALL USING (true);
CREATE POLICY "Public Read/Write Access" ON settlements FOR ALL USING (true);
