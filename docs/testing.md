# Тестирование

## Базовые проверки

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test tool
dart analyze lib test integration_test tool
flutter test
```

`test/student/` проверяет хранилище, авторизацию, редакторы, валидацию, вложения, профиль, адаптивность, навигацию, уведомления и канбан. Проверяются промежуточные кадры переходов, порядок карточек, автопрокрутка, отмена, задержка и ошибка сохранения. `test/legacy/` сохраняет регрессионные проверки прежней версии.

## Локальный backend

```sh
./scripts/start_students_backend.sh
STUDENT_BACKEND_TEST=1 flutter test test/student/student_backend_test.dart
```

Тест работает только с API на порту 55421. Он создаёт синтетических пользователей и проверяет Auth, CRUD, RLS, связи и приватные файлы.

## Отдельное HTTPS-окружение

Сетевые проверки по умолчанию пропускаются. Для них нужны игнорируемые `config/student-hosted.json` и `config/student-hosted-test-users.json`. Сначала подготовьте отдельное тестовое окружение.

```sh
TASKO_HOSTED_ORDER_TEST=1 flutter test test/student/student_hosted_order_test.dart
TASKO_HOSTED_TEST=1 flutter test test/student/student_hosted_backend_test.dart
```

Первый тест создаёт временные записи и проверяет порядок после загрузки другим клиентом. Второй проверяет подготовленный набор тестовых аккаунтов и точные размеры fixtures, поэтому не подходит для произвольной базы. Оба очищают только созданные ими временные записи.

## Интеграционные сценарии

`integration_test/legacy/` содержит отдельные сценарии прежней версии. Для них необходимо собственное тестовое окружение соответствующей схемы. Браузерная демонстрация основного приложения описана в [настройке и запуске](getting-started.md).
