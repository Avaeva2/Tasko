# Настройка и запуск

## Требования

- Flutter 3.47.6 с Dart 3.13.
- Android SDK и JDK 17 для Android; Xcode для iOS.
- Docker и Supabase CLI — только для локального backend.
- Node.js 22+ — только для браузерной демонстрации.

```sh
flutter pub get
flutter run --dart-define=TASKO_STUDENTS_DEMO=true
```

Для выбора устройства используйте `flutter devices` и `flutter run -d <device-id>`.

## Аккаунт и сервер

Скопируйте `config/student-hosted.example.json` в `config/student-hosted.json`, заполните URL проекта и клиентский ключ. Приложению достаточно publishable/anon key. Привилегированные серверные ключи не нужны.

В Supabase примените миграцию из `supabase/migrations/`. Она создаёт таблицы профилей, предметов, пар, заданий и приватный bucket `student-materials`; доступ ограничен владельцем через RLS.

Включите email-аутентификацию. При включённом подтверждении email настройте отправку писем и допустимые redirect URL в своём проекте Supabase.

```sh
flutter run --dart-define-from-file=config/student-hosted.json
```

Без URL и ключа доступен только явно выбранный режим демо. Ошибка сети не переводит пользователя из аккаунта в демо.

## Локальный Supabase

```sh
./scripts/start_students_backend.sh
./scripts/run_students_web.sh --local
```

Скрипт использует отдельный workdir `local-students/`, применяет миграции без сброса существующей базы и записывает клиентскую конфигурацию в `config/student-local.json`.

| Сервис | Адрес |
| --- | --- |
| Приложение | http://127.0.0.1:49182 |
| Supabase API | http://127.0.0.1:55421 |
| Supabase Studio | http://127.0.0.1:55423 |
| Тестовая почта | http://127.0.0.1:55424 |

`./scripts/run_students_web.sh --demo` собирает веб-демо; без аргументов скрипт предпочитает `config/student-hosted.json`, если файл существует. Для своей конфигурации задайте `TASKO_STUDENTS_CONFIG`.

## Пути к SDK

Обычно достаточно добавить Flutter в `PATH` и задать `ANDROID_HOME` / `JAVA_HOME`. Скрипт `scripts/flutter.sh` также принимает `FLUTTER_BIN`, а `scripts/supabase.sh` — `TASKO_SUPABASE_BIN`.

Для постоянных настроек своей машины можно создать игнорируемый `config/toolchain.local.sh` с экспортами этих переменных. Его содержимое не публикуется.

## Браузерная демонстрация

```sh
npm ci
npx playwright install chromium
./scripts/run_students_web.sh --demo
# В другом терминале:
npm run demo
```

Сценарии демонстрации используют только отдельный браузерный контекст и режим демо. Они проверяют канбан, расписание, создание задания и материалы; серверные данные аккаунтов не изменяются. Запись и результаты сохраняются в `artifacts/`.
