-- Migration: 20260901_validate_constraints
-- Scopo: completare i vincoli introdotti da 20260829_lockdown_anon_writes.sql.
--
-- Quella migrazione aveva lasciato tre CHECK come NOT VALID perche' al momento
-- della scrittura il contenuto delle righe gia' presenti non era ispezionabile.
-- Un vincolo NOT VALID e' comunque applicato a INSERT e UPDATE, quindi il buco
-- non era sulle righe nuove; restava pero' il dubbio sulle vecchie e, soprattutto,
-- il planner non puo' fare affidamento su un vincolo non validato.
--
-- Verificato sul dato live prima di scrivere questo file (83 expenses, 1 settlement):
--   expenses.amount     va da 4 a 3000            -> dentro (0, 100000]
--   settlements.amount  vale 1718.19              -> dentro [0, 100000]
--   created_by/settled_by contengono solo 'Matteo' e 'Elena'
--   notes    e' lunga al massimo 33 caratteri     -> sotto i 2000
--   category e' lunga al massimo 10 caratteri     -> sotto i 50
-- quindi VALIDATE non puo' fallire e non serve alcuna bonifica preventiva.
--
-- VALIDATE CONSTRAINT prende un lock SHARE UPDATE EXCLUSIVE: fa una scansione
-- della tabella ma non blocca ne' letture ne' scritture concorrenti.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Promozione dei vincoli da NOT VALID a validati
-- ---------------------------------------------------------------------------
ALTER TABLE public.expenses    VALIDATE CONSTRAINT expenses_notes_len;
ALTER TABLE public.settlements VALIDATE CONSTRAINT settlements_amount_sane;
ALTER TABLE public.settlements VALIDATE CONSTRAINT settlements_settled_by_known;

-- ---------------------------------------------------------------------------
-- 2. Il campo rimasto senza limiti: category
-- ---------------------------------------------------------------------------
-- L'INSERT diretto resta aperto ai dispositivi arruolati, e `category` e' TEXT
-- senza vincoli: una singola riga potrebbe portarsi dietro megabyte di testo.
-- Le categorie sono un elenco chiuso definito nel client (App.tsx:51), ma un
-- CHECK IN (...) legherebbe il database a quell'elenco e costringerebbe a una
-- migrazione per ogni categoria aggiunta. Un tetto sulla lunghezza chiude
-- l'abuso senza creare quell'accoppiamento.
ALTER TABLE public.expenses DROP CONSTRAINT IF EXISTS expenses_category_len;
ALTER TABLE public.expenses ADD  CONSTRAINT expenses_category_len
  CHECK (char_length(category) BETWEEN 1 AND 50);

COMMIT;
