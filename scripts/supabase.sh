#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ -n "${TASKO_SUPABASE_BIN:-}" ] && [ -x "$TASKO_SUPABASE_BIN" ]; then
  exec "$TASKO_SUPABASE_BIN" "$@"
fi
if command -v supabase >/dev/null 2>&1; then
  exec supabase "$@"
fi
if [ -x tools/bin/supabase ]; then
  exec tools/bin/supabase "$@"
fi
printf '%s\n' 'Supabase CLI не найден. Установите его или задайте TASKO_SUPABASE_BIN.' >&2
exit 1
