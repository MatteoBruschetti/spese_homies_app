-- Migration: 20260830_1_device_auth_setup
-- Passo 1 di 2. Crea l'infrastruttura per l'autorizzazione per dispositivo e
-- genera i tre token, MA NON tocca ancora le policy: dopo questo script il
-- database si comporta esattamente come prima.
--
-- Il motivo della separazione: le policy del passo 2 dipenderanno dal fatto che
-- PostgREST inoltri l'header `x-device-token` fino a Postgres. Se lo agganciassimo
-- subito e il meccanismo non funzionasse, resteremmo chiusi fuori dal database.
-- Qui creiamo la sonda `whoami_device()` per dimostrare che funziona.
--
-- Nota implementativa: niente pgcrypto. `sha256()` e `gen_random_uuid()` sono
-- funzioni core di Postgres, mentre `digest()`/`gen_random_bytes()` di pgcrypto
-- vivrebbero nello schema `extensions`, fuori dal search_path bloccato che le
-- funzioni SECURITY DEFINER qui sotto impostano per sicurezza.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Registro dei dispositivi
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.devices (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label      TEXT NOT NULL UNIQUE,
  token_hash TEXT NOT NULL UNIQUE,   -- sha256 esadecimale, mai il token in chiaro
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  revoked_at TIMESTAMPTZ
);

-- RLS attiva senza policy: invisibile ad anon in lettura e in scrittura.
-- Accessibile solo da service_role, cioe' dal dashboard.
ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.devices FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Lettura dell'header e confronto col registro
-- ---------------------------------------------------------------------------
-- PostgREST espone gli header della richiesta nella GUC `request.headers`,
-- con i nomi in minuscolo. STABLE: valutata una volta per query, non per riga.
CREATE OR REPLACE FUNCTION public.device_token()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT nullif(current_setting('request.headers', true)::json ->> 'x-device-token', '');
$$;

CREATE OR REPLACE FUNCTION public.device_token_hash()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  -- Il fallback '~nessun-token~' evita che un header assente produca NULL e
  -- quindi un confronto NULL = NULL, che in SQL non e' mai vero ma e' meglio
  -- non doverci ragionare sopra.
  SELECT encode(sha256(convert_to(coalesce(public.device_token(), '~nessun-token~'), 'UTF8')), 'hex');
$$;

CREATE OR REPLACE FUNCTION public.is_authorized_device()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.devices d
     WHERE d.revoked_at IS NULL
       AND d.token_hash = public.device_token_hash()
  );
$$;

-- Sonda diagnostica: distingue i tre casi che altrimenti si confonderebbero
-- tutti in un generico "non funziona".
CREATE OR REPLACE FUNCTION public.whoami_device()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT coalesce(
    (SELECT d.label
       FROM public.devices d
      WHERE d.revoked_at IS NULL
        AND d.token_hash = public.device_token_hash()),
    CASE WHEN public.device_token() IS NULL
         THEN 'nessun-header'
         ELSE 'token-sconosciuto'
    END
  );
$$;

REVOKE ALL ON FUNCTION public.device_token()        FROM PUBLIC;
REVOKE ALL ON FUNCTION public.device_token_hash()   FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_authorized_device() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.whoami_device()       FROM PUBLIC;

-- Solo la sonda e' chiamabile dall'esterno: serve all'app per sapere se il
-- dispositivo e' arruolato, e a noi per verificare il meccanismo adesso.
GRANT EXECUTE ON FUNCTION public.whoami_device() TO anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Generazione dei tre token
-- ---------------------------------------------------------------------------
-- I token in chiaro compaiono UNA SOLA VOLTA, nel risultato di questa query.
-- Nel database ne resta solo lo sha256: se li perdi non sono recuperabili,
-- si rigenerano cancellando la riga corrispondente e rieseguendo questo blocco.
--
-- MATERIALIZED e' obbligatorio: la CTE e' referenziata due volte e contiene una
-- funzione volatile. Se venisse inlineata, il token inserito e quello mostrato
-- sarebbero diversi e nessun dispositivo riuscirebbe mai ad autenticarsi.
WITH nuovi AS MATERIALIZED (
  SELECT label,
         replace(gen_random_uuid()::text, '-', '') ||
         replace(gen_random_uuid()::text, '-', '') AS token
    FROM unnest(ARRAY['mac-matteo', 'android-matteo', 'ios-elena']) AS label
),
inseriti AS (
  INSERT INTO public.devices (label, token_hash)
  SELECT label, encode(sha256(convert_to(token, 'UTF8')), 'hex')
    FROM nuovi
  ON CONFLICT (label) DO NOTHING
  RETURNING label
)
SELECT n.label,
       n.token,
       '#t=' || n.token AS frammento_da_appendere_alla_url
  FROM nuovi n
  JOIN inseriti i ON i.label = n.label
 ORDER BY n.label;

COMMIT;

NOTIFY pgrst, 'reload schema';
