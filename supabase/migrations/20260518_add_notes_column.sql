-- Migration: Add notes column to expenses table
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS notes TEXT;
