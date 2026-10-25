# Сборка

## Web

```sh
flutter build web --release --no-web-resources-cdn --no-wasm-dry-run \
  --dart-define-from-file=config/student-hosted.json
```

Результат находится в `build/web/`; каталог можно разместить на статическом HTTPS-хостинге. Для автономного демо вместо файла конфигурации передайте `--dart-define=TASKO_STUDENTS_DEMO=true`.

## Android

```sh
./scripts/build_android.sh
```

Нужны Android SDK, Build Tools и JDK 17. Скрипт использует `ANDROID_HOME` / `ANDROID_SDK_ROOT`, собирает ARM64 release, проверяет подпись и отсутствие `DEBUGGABLE`, затем сохраняет APK в `artifacts/tasko-students-release.apk`.

Параметры: `TASKO_ANDROID_CONFIG` — JSON-конфигурация, `TASKO_ANDROID_OUTPUT` — путь APK, `TASKO_ANDROID_SDK` — SDK, `TASKO_ANDROID_BUILD_TOOLS` — каталог Build Tools. По умолчанию выбирается hosted-конфигурация, затем локальная.

Для установки без удаления данных:

```sh
adb install -r artifacts/tasko-students-release.apk
```

Для тестирования Gradle использует debug-ключ. Перед распространением настройте собственный release signing config в `android/app/build.gradle.kts`; ключ и `android/key.properties` должны оставаться вне Git. При обновлении уже установленного приложения сохраняйте прежний ключ подписи.

## iOS

```sh
flutter build ios --release --dart-define-from-file=config/student-hosted.json
```

Нужны macOS, Xcode и настроенная команда подписи Apple Developer. Сертификаты и provisioning profiles не входят в репозиторий. Для симулятора используется `flutter build ios --simulator --debug`.

## Иконки

Исходный PNG — `assets/student/tasko-logo.png`. Размеры Android, iOS и Web воспроизводятся командой:

```sh
python3 tool/generate_student_brand_icons.py
```

Для этого вспомогательного скрипта требуется macOS `sips`. Готовые иконки уже входят в исходники; для обычной сборки запускать его не нужно.
