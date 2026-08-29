-- ATTENZIONE: questa migrazione e' gia' applicata in produzione e il blocco DO
-- in fondo ricrea `"Public Access" FOR ALL USING (true)` se una policy con QUEL
-- nome non esiste. Dopo 20260829_lockdown_anon_writes.sql le policy si chiamano
-- diversamente, quindi rieseguirla riaprirebbe l'accesso pubblico in scrittura.
--
-- Lo storico remoto e' stato allineato il 2026-08-29 con `supabase migration
-- repair --status applied`, quindi `supabase db push` NON riesegue piu' questo
-- file (verificato: `db push --dry-run` risponde "Remote database is up to date").
-- Resta valido il divieto di eseguirlo a mano.

-- Migration: 20260517_init_schema
-- Description: Create expenses and settlements tables for "Spese di Coppia"

-- Enable pgcrypto for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create Expenses table
CREATE TABLE IF NOT EXISTS public.expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  amount FLOAT NOT NULL,
  category TEXT NOT NULL DEFAULT 'Altro',
  created_by TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  notes TEXT
);

-- Create Settlements table
CREATE TABLE IF NOT EXISTS public.settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  amount FLOAT NOT NULL,
  settled_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  settled_by TEXT NOT NULL
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements ENABLE ROW LEVEL SECURITY;

-- Public Access Policy (MVP)
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public Access' AND tablename = 'expenses') THEN
        CREATE POLICY "Public Access" ON public.expenses FOR ALL USING (true) WITH CHECK (true);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'Public Access' AND tablename = 'settlements') THEN
        CREATE POLICY "Public Access" ON public.settlements FOR ALL USING (true) WITH CHECK (true);
    END IF;
END $$;
