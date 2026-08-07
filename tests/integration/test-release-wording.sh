#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GUI="$ROOT/gui/WineVideoPatcher.swift"
PATCHER="$ROOT/patcher/patch.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

rg -q 'CrossOver 26\.2 & 26\.3' "$GUI" || fail "GUI does not name both supported CrossOver versions"

if rg -n 'Ninja Gaiden|Nioh|Persona 5' "$GUI"; then
  fail "GUI contains game-specific wording"
fi

if rg -n -i 'private draft|experimental' "$GUI" "$PATCHER"; then
  fail "release surface still contains draft or experimental wording"
fi

printf 'PASS: generic release wording\n'
