#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/environment.sh
if [ -n "${FLUTTER_BIN:-}" ] && [ -x "$FLUTTER_BIN" ]; then
  exec "$FLUTTER_BIN" "$@"
fi
if command -v flutter >/dev/null 2>&1; then
  exec flutter "$@"
fi
printf '%s\n' 'Flutter SDK не найден. Добавьте flutter в PATH или задайте FLUTTER_BIN.' >&2
exit 1
