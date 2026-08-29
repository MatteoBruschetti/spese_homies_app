#!/usr/bin/env bash
#
# Esegue SQL sul database Supabase tramite la Management API (HTTPS).
#
# Perche' non la CLI: `supabase db push` riesegue TUTTE le migrazioni, inclusa
# 20260517_initial_schema.sql, il cui blocco DO ricrea "Public Access"
# FOR ALL USING (true) e riaprirebbe l'accesso pubblico in scrittura. Questo
# script esegue solo cio' che gli passi, e non tocca lo storico migrazioni.
#
# Uso:
#   ./scripts/db.sh "select count(*) from public.expenses;"
#   ./scripts/db.sh -f supabase/migrations/20260901_qualcosa.sql
#
# Credenziali: SUPABASE_ACCESS_TOKEN da .env.local (gitignored, mai committato).
# ATTENZIONE: quel token ha accesso all'intero account Supabase, non al solo
# progetto, e questa API gira come utente `postgres`. Ogni query e' privilegiata.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env.local" ] || { echo "manca $ROOT/.env.local" >&2; exit 1; }
# NON usare `. "$ROOT/.env.local"`: i valori non quotati che contengono `$`
# verrebbero espansi dalla shell e arriverebbero corrotti.
SUPABASE_ACCESS_TOKEN="$(python3 "$ROOT/scripts/env-get.py" SUPABASE_ACCESS_TOKEN)"
[ -n "$SUPABASE_ACCESS_TOKEN" ] || { echo "SUPABASE_ACCESS_TOKEN vuoto" >&2; exit 1; }

REF="${SUPABASE_PROJECT_REF:-tjssmfntbuxubytujcdj}"

if [ "${1:-}" = "-f" ]; then
  [ -n "${2:-}" ] || { echo "uso: $0 -f <file.sql>" >&2; exit 1; }
  [ -f "$2" ]     || { echo "file non trovato: $2" >&2; exit 1; }
  SQL="$(cat "$2")"
else
  SQL="${1:-}"
  [ -n "$SQL" ] || { echo "uso: $0 '<sql>'  oppure  $0 -f <file.sql>" >&2; exit 1; }
fi

# json.dumps gestisce apici, dollari e a capo senza doverli sfuggire a mano.
BODY="$(SQL="$SQL" python3 -c 'import json,os; print(json.dumps({"query": os.environ["SQL"]}))')"

curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$BODY"
echo
