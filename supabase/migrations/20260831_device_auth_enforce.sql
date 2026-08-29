-- Migration: 20260831_device_auth_enforce
-- Passo 2 di 2. Aggancia le policy all'autorizzazione per dispositivo creata da
-- 20260830_device_auth_setup.sql. Da qui in avanti una richiesta che porta solo
-- la chiave pubblica del repo, senza header `x-device-token` valido, ottiene
-- ZERO righe invece di tutte.
--
-- PREREQUISITO VERIFICATO PRIMA DI SCRIVERE QUESTO FILE: una chiamata reale a
-- whoami_device() risponde 'nessun-header' senza header e 'token-sconosciuto'
-- con un token inventato, quindi PostgREST inoltra davvero l'header a Postgres.
--
-- PREREQUISITO PER TE: i tre dispositivi devono essere gia' arruolati (link
-- aperto una volta su ognuno) e il frontend aggiornato deve essere gia' online,
-- altrimenti l'app smette di vedere i dati appena questo script gira.
-- In fondo al file trovi il rollback, commentato.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Permessi di esecuzione
-- ---------------------------------------------------------------------------
-- Le espressioni delle policy RLS vengono valutate con i privilegi di CHI fa la
-- query, non del proprietario della tabella: senza questi GRANT ogni SELECT di
-- anon fallirebbe con "permission denied for function".
-- Nessuna delle tre rivela informazioni: operano solo sul token che il chiamante
-- ha gia' mandato, e restituiscono un booleano o l'hash del proprio token.
GRANT EXECUTE ON FUNCTION public.device_token()         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.device_token_hash()    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_authorized_device() TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Le policy passano da "chiunque" a "dispositivo arruolato"
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "public_select" ON public.expenses;
DROP POLICY IF EXISTS "public_insert" ON public.expenses;
DROP POLICY IF EXISTS "public_select" ON public.settlements;
DROP POLICY IF EXISTS "public_insert" ON public.settlements;

CREATE POLICY "device_select" ON public.expenses
  FOR SELECT TO anon, authenticated USING (public.is_authorized_device());
CREATE POLICY "device_insert" ON public.expenses
  FOR INSERT TO anon, authenticated WITH CHECK (public.is_authorized_device());

CREATE POLICY "device_select" ON public.settlements
  FOR SELECT TO anon, authenticated USING (public.is_authorized_device());
CREATE POLICY "device_insert" ON public.settlements
  FOR INSERT TO anon, authenticated WITH CHECK (public.is_authorized_device());

-- ---------------------------------------------------------------------------
-- 3. Anche le RPC di mutazione, che l'RLS non copre
-- ---------------------------------------------------------------------------
-- delete_expense, update_expense e delete_settlement sono SECURITY DEFINER:
-- girano come owner e quindi SCAVALCANO le policy appena create. Senza il
-- controllo esplicito qui sotto resterebbero la porta aperta di tutto il resto.
CREATE OR REPLACE FUNCTION public.delete_expense(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_authorized_device() THEN
    RAISE EXCEPTION 'Dispositivo non autorizzato.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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
  IF NOT public.is_authorized_device() THEN
    RAISE EXCEPTION 'Dispositivo non autorizzato.' USING ERRCODE = 'insufficient_privilege';
  END IF;

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
  IF NOT public.is_authorized_device() THEN
    RAISE EXCEPTION 'Dispositivo non autorizzato.' USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM public.assert_mutation_budget();

  INSERT INTO public.settlements_archive (action, id, amount, settled_at, settled_by)
  SELECT 'delete', s.id, s.amount, s.settled_at, s.settled_by
    FROM public.settlements s
   WHERE s.id = p_id;

  DELETE FROM public.settlements WHERE id = p_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- ROLLBACK D'EMERGENZA
-- ---------------------------------------------------------------------------
-- Se dopo questo script l'app non vede piu' i dati e non riesci a capire
-- perche', esegui il blocco qui sotto: riporta la lettura e l'inserimento ad
-- accesso pubblico (cioe' allo stato dopo il solo lockdown) senza perdere ne'
-- dispositivi ne' archivio. Le RPC continuano a richiedere il dispositivo, quindi
-- toglie il blocco alla lettura ma non riapre le cancellazioni.
--
-- BEGIN;
--   DROP POLICY IF EXISTS "device_select" ON public.expenses;
--   DROP POLICY IF EXISTS "device_insert" ON public.expenses;
--   DROP POLICY IF EXISTS "device_select" ON public.settlements;
--   DROP POLICY IF EXISTS "device_insert" ON public.settlements;
--   CREATE POLICY "public_select" ON public.expenses
--     FOR SELECT TO anon, authenticated USING (true);
--   CREATE POLICY "public_insert" ON public.expenses
--     FOR INSERT TO anon, authenticated WITH CHECK (true);
--   CREATE POLICY "public_select" ON public.settlements
--     FOR SELECT TO anon, authenticated USING (true);
--   CREATE POLICY "public_insert" ON public.settlements
--     FOR INSERT TO anon, authenticated WITH CHECK (true);
-- COMMIT;
-- NOTIFY pgrst, 'reload schema';
