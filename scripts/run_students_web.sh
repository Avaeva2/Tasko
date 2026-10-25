#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TASKO_STUDENT_DEMO=false
TASKO_STUDENT_LOCAL=false
for TASKO_STUDENT_ARG in "$@"; do
  case "$TASKO_STUDENT_ARG" in
    --demo) TASKO_STUDENT_DEMO=true ;;
    --local) TASKO_STUDENT_LOCAL=true ;;
    *) printf '%s\n' 'Использование: run_students_web.sh [--demo] [--local]' >&2; exit 2 ;;
  esac
done
TASKO_STUDENT_CONFIG="${TASKO_STUDENTS_CONFIG:-}"
if [ -z "$TASKO_STUDENT_CONFIG" ]; then
  if [ "$TASKO_STUDENT_LOCAL" = false ] && [ -s config/student-hosted.json ]; then
    TASKO_STUDENT_CONFIG=config/student-hosted.json
  else
    TASKO_STUDENT_CONFIG=config/student-local.json
  fi
fi
if [ -f "$TASKO_STUDENT_CONFIG" ]; then
  ./scripts/flutter.sh build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define="TASKO_STUDENTS_DEMO=$TASKO_STUDENT_DEMO" --dart-define-from-file="$TASKO_STUDENT_CONFIG"
else
  ./scripts/flutter.sh build web --release --no-web-resources-cdn --no-wasm-dry-run --dart-define="TASKO_STUDENTS_DEMO=$TASKO_STUDENT_DEMO"
fi
exec python3 scripts/serve_students.py
