-- Migration: 20260829_lockdown_anon_writes
-- Scopo: togliere al ruolo `anon` la possibilita' di modificare o cancellare
-- righe IN BLOCCO. Prima di questa migrazione le policy erano
-- `FOR ALL USING (true)`, quindi una singola richiesta anonima
--     DELETE /rest/v1/expenses?amount=gt.0
-- cancellava tutto lo storico in modo irreversibile.
--
-- Dopo questa migrazione:
--   * anon puo' solo SELECT e INSERT direttamente sulle tabelle;
--   * modifica e cancellazione passano per funzioni che agiscono su UNA riga
--     per chiamata, identificata dalla primary key;
--   * ogni riga cancellata o modificata viene copiata in una tabella di
--     archivio che anon non puo' ne' leggere ne' scrivere, quindi il danno e'
--     sempre recuperabile dal dashboard Supabase;
--   * oltre 15 mutazioni in 10 minuti le funzioni si rifiutano di procedere.
--
-- Cosa questa migrazione NON fa: i dati restano leggibili pubblicamente.
-- Renderli privati richiede un'autenticazione, esclusa per scelta esplicita.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Tabelle di archivio (invisibili ad anon)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.expenses_archive (
  archive_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  action      TEXT NOT NULL,            -- 'delete' | 'update'
  id          UUID NOT NULL,            -- id della riga originale
  amount      FLOAT,
  category    TEXT,
  created_by  TEXT,
  created_at  TIMESTAMPTZ,
  notes       TEXT
);

CREATE TABLE IF NOT EXISTS public.settlements_archive (
  archive_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  archived_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  action      TEXT NOT NULL,
  id          UUID NOT NULL,
  amount      FLOAT,
  settled_at  TIMESTAMPTZ,
  settled_by  TEXT
);

-- RLS attiva SENZA alcuna policy: per anon e authenticated l'accesso e' negato
-- in lettura e in scrittura. Restano leggibili da service_role, cioe' dal
-- dashboard Supabase, che e' esattamente il canale di recupero.
ALTER TABLE public.expenses_archive    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.settlements_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.expenses_archive    FROM anon, authenticated;
REVOKE ALL ON public.settlements_archive FROM anon, authenticated;

-- Indici usati dal controllo di budget qui sotto.
CREATE INDEX IF NOT EXISTS expenses_archive_archived_at_idx
  ON public.expenses_archive (archived_at DESC);
CREATE INDEX IF NOT EXISTS settlements_archive_archived_at_idx
  ON public.settlements_archive (archived_at DESC);

-- ---------------------------------------------------------------------------
-- 2. Policy: lettura e inserimento pubblici, nient'altro
-- ---------------------------------------------------------------------------
-- Il repo contiene due nomi diversi per le stesse policy ("Public Access" nella
-- migrazione, "Public Read/Write Access" in supabase.sql) e non e' verificabile
-- quale sia realmente attivo, quindi le rimuoviamo tutte per nome effettivo.
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT policyname, tablename
      FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename IN ('expenses', 'settlements')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', p.policyname, p.tablename);
  END LOOP;
END $$;

CREATE POLICY "public_select" ON public.expenses
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "public_insert" ON public.expenses
  FOR INSERT TO anon, authenticated WITH CHECK (true);

CREATE POLICY "public_select" ON public.settlements
  FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY "public_insert" ON public.settlements
  FOR INSERT TO anon, authenticated WITH CHECK (true);

-- Secondo cancello: anche i GRANT a livello di tabella, non solo l'RLS.
REVOKE UPDATE, DELETE ON public.expenses    FROM anon, authenticated;
REVOKE UPDATE, DELETE ON public.settlements FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Vincoli sui dati (l'INSERT resta aperto, quindi va delimitato)
-- ---------------------------------------------------------------------------
-- Verificato sul dato live prima di scrivere: amount va da 4 a 3000 e
-- created_by contiene solo 'Elena' e 'Matteo', quindi questi due vincoli
-- possono essere validati subito senza far fallire la migrazione.
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_amount_sane;
ALTER TABLE public.expenses ADD  CONSTRAINT expenses_amount_sane
  CHECK (amount > 0 AND amount <= 100000);

ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_created_by_known;
ALTER TABLE public.expenses ADD  CONSTRAINT expenses_created_by_known
  CHECK (created_by IN ('Matteo', 'Elena'));

-- La lunghezza delle note non e' verificabile dall'esterno senza leggerne il
-- contenuto, quindi NOT VALID: vincola le righe nuove e modificate, tollera
-- quelle gia' presenti.
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_notes_len;
ALTER TABLE public.expenses ADD  CONSTRAINT expenses_notes_len
  CHECK (notes IS NULL OR char_length(notes) <= 2000) NOT VALID;

-- Le settlements non vengono mai modificate dall'app, solo inserite e
-- cancellate: NOT VALID e' quindi equivalente a un vincolo pieno sulle righe
-- nuove, senza alcun rischio sull'unica riga esistente.
ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_amount_sane;
ALTER TABLE public.settlements ADD  CONSTRAINT settlements_amount_sane
  CHECK (amount >= 0 AND amount <= 100000) NOT VALID;

ALTER TABLE public.settlements DROP CONSTRAINT IF EXISTS settlements_settled_by_known;
ALTER TABLE public.settlements ADD  CONSTRAINT settlements_settled_by_known
  CHECK (settled_by IN ('Matteo', 'Elena')) NOT VALID;

-- ---------------------------------------------------------------------------
-- 4. Budget di mutazioni
-- ---------------------------------------------------------------------------
-- Non e' concedibile ad anon: viene invocata solo dall'interno delle funzioni
-- SECURITY DEFINER qui sotto, che girano come owner.
CREATE OR REPLACE FUNCTION public.assert_mutation_budget()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recent integer;
BEGIN
  SELECT (SELECT count(*) FROM public.expenses_archive
           WHERE archived_at > now() - interval '10 minutes')
       + (SELECT count(*) FROM public.settlements_archive
           WHERE archived_at > now() - interval '10 minutes')
    INTO v_recent;

  IF v_recent >= 15 THEN
    RAISE EXCEPTION
      'Troppe modifiche ravvicinate (% negli ultimi 10 minuti). Riprova fra qualche minuto.',
      v_recent
      USING ERRCODE = 'check_violation';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.assert_mutation_budget() FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 5. Mutazioni a riga singola
-- ---------------------------------------------------------------------------
-- Ognuna filtra sulla primary key, quindi non puo' toccare piu' di una riga
-- per chiamata, qualunque cosa il chiamante metta nel body.
CREATE OR REPLACE FUNCTION public.delete_expense(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.assert_mutation_budget();

  INSERT INTO public.expenses_archive (action, id, amount, category, created_by, created_at, notes)
  SELECT 'delete', e.id, e.amount, e.category, e.created_by, e.created_at, e.notes
    FROM public.expenses e
   WHERE e.id = p_id;

  DELETE FROM public.expenses WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_expense(
  p_id         uuid,
  p_amount     double precision,
  p_category   text,
  p_created_at timestamptz,
  p_notes      text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.assert_mutation_budget();

  INSERT INTO public.expenses_archive (action, id, amount, category, created_by, created_at, notes)
  SELECT 'update', e.id, e.amount, e.category, e.created_by, e.created_at, e.notes
    FROM public.expenses e
   WHERE e.id = p_id;

  UPDATE public.expenses
     SET amount     = p_amount,
         category   = p_category,
         created_at = p_created_at,
         notes      = p_notes
   WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_settlement(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.assert_mutation_budget();

  INSERT INTO public.settlements_archive (action, id, amount, settled_at, settled_by)
  SELECT 'delete', s.id, s.amount, s.settled_at, s.settled_by
    FROM public.settlements s
   WHERE s.id = p_id;

  DELETE FROM public.settlements WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_expense(uuid)    FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_settlement(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_expense(uuid, double precision, text, timestamptz, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.delete_expense(uuid)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_settlement(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_expense(uuid, double precision, text, timestamptz, text) TO anon, authenticated;

COMMIT;

-- Forza PostgREST a ricaricare la schema cache, cosi' le nuove RPC sono
-- raggiungibili subito invece che dopo qualche secondo.
NOTIFY pgrst, 'reload schema';
