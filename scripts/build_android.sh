#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

. ./scripts/environment.sh
tasko_android_sdk="${TASKO_ANDROID_SDK:-${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}}"
if [[ -z "$tasko_android_sdk" ]]; then
  printf '%s\n' 'Задайте ANDROID_HOME или ANDROID_SDK_ROOT.' >&2
  exit 1
fi
if [[ -n "${TASKO_ANDROID_CONFIG:-}" ]]; then
  tasko_android_config="$TASKO_ANDROID_CONFIG"
elif [[ -s config/student-hosted.json ]]; then
  tasko_android_config=config/student-hosted.json
else
  tasko_android_config=config/student-local.json
fi
tasko_android_output="${TASKO_ANDROID_OUTPUT:-artifacts/tasko-students-release.apk}"
export ANDROID_HOME="$tasko_android_sdk"
export ANDROID_SDK_ROOT="$tasko_android_sdk"
if [[ -n "${JAVA_HOME:-}" ]]; then
  export PATH="$JAVA_HOME/bin:$tasko_android_sdk/platform-tools:$PATH"
else
  export PATH="$tasko_android_sdk/platform-tools:$PATH"
fi

if [[ ! -s "$tasko_android_config" ]]; then
  printf '%s\n' 'Нет конфигурации Students; сначала запустите scripts/start_students_backend.sh.' >&2
  exit 1
fi
mkdir -p artifacts
if [[ -n "${TASKO_SUPABASE_URL:-}" ]]; then
  set -- "--dart-define=SUPABASE_URL=$TASKO_SUPABASE_URL" "$@"
fi
./scripts/flutter.sh build apk --release --target-platform android-arm64 \
  --dart-define-from-file="$tasko_android_config" \
  "$@" \
  2>&1 | tee artifacts/student-android-build.log
mkdir -p "$(dirname "$tasko_android_output")"
cp build/app/outputs/flutter-apk/app-release.apk "$tasko_android_output"
tasko_build_tools="${TASKO_ANDROID_BUILD_TOOLS:-$(find "$tasko_android_sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)}"
if [[ ! -x "$tasko_build_tools/apksigner" || ! -x "$tasko_build_tools/aapt" ]]; then
  printf '%s\n' 'Android Build Tools не найдены.' >&2
  exit 1
fi
"$tasko_build_tools/apksigner" verify --verbose \
  "$tasko_android_output" > artifacts/student-android-signature.log
"$tasko_build_tools/aapt" dump badging \
  "$tasko_android_output" > artifacts/student-android-info.log
if grep -q '^application-debuggable' artifacts/student-android-info.log; then
  printf '%s\n' 'Ошибка: APK допускает отладку.' >&2
  exit 1
fi
shasum -a 256 "$tasko_android_output" > artifacts/student-android-sha256.log
