"""Legge un singolo valore da .env.local in modo letterale.

Il sourcing shell (`. ./.env.local`) NON va usato su questo file: i valori non
quotati che contengono `$` verrebbero espansi dalla shell e arriverebbero
corrotti o vuoti. E' esattamente cosi' che la password del database e' sembrata
per un po' "non piu' valida".

Stampa solo il valore richiesto, senza a capo finale.
"""

import pathlib
import re
import sys

if len(sys.argv) != 2:
    sys.exit("uso: env-get.py NOME_VARIABILE")

path = pathlib.Path(__file__).resolve().parent.parent / ".env.local"
if not path.exists():
    sys.exit(f"manca {path}")

pattern = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")

for line in path.read_text().splitlines():
    if line.lstrip().startswith("#"):
        continue
    match = pattern.match(line)
    if not match or match.group(1) != sys.argv[1]:
        continue
    value = match.group(2)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    print(value, end="")
    break
else:
    sys.exit(f"{sys.argv[1]} non presente in .env.local")
