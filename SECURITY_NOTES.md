# Security notes

## Part A: login bypass removed

- The Flutter client previously fabricated admin, caretaker, and student sessions
  in `flutter_app/lib/services/api_service.dart` when login timed out or the
  backend could not be reached. Those credentials and demo tokens have been
  removed; sign-in now fails closed when the server is unavailable.
- `flutter_app/lib/screens/auth/login_screen.dart` previously prefilled demo
  email/password values and displayed them beneath the form. Those defaults and
  hints have been removed.
- `my_server/server.js` previously inserted public demo caretaker and student
  accounts when the users table was empty. User seeding has been removed.
  Existing plaintext database passwords are rejected by the bcrypt-only login
  flow until the account completes password reset.
- Public registration previously accepted `role: caretaker` from the request.
  It now always creates a student account; caretaker accounts must be provisioned
  by a trusted process.
- `my_server/server.log` contained those demo credentials and local database
  connection details. The historical log has been redacted.

## Secret and credential audit

- `my_server/.env` was committed in earlier history (`772b473` and
  `959565b`) with non-placeholder `API_SECRET_KEY` and `DB_PASSWORD` values.
  Although the current file is ignored and no longer tracked, rotate both values
  before going live. The historical DB host, username, and database name were
  also exposed as configuration metadata.
- `docker-compose.yml` also contained a committed database password. It now
  reads credentials from environment variables. Rotate the historical database
  password anywhere it was used before deployment.
- `my_server/server.js` contained a fixed fallback telemetry API key; the
  fallback is removed. Rotate any telemetry key that matched that historical
  source value because it was committed in Git history.
- The working tree has ignored local secrets in `my_server/.env` and
  `flutter_app/.env`. `flutter_app/.env` was not found in Git history; the
  backend `.env` history is described above.
  The Flutter `.env` was previously listed as an app asset, so map API keys could
  be packaged into local builds. It is no longer bundled or loaded; use
  `--dart-define` and restrict/rotate those client keys if they were used in
  distributed builds.
- `my_server/__pycache__/esp32_server.cpython-312.pyc` was tracked and has been
  removed from the Git index; ignore rules now cover Python caches and build
  outputs.
- Driver names and mobile numbers in `my_server/server.js` are sample seed data,
  not authentication secrets; replace them before using real fleet records.

Passwords are stored as bcrypt hashes for new and reset accounts. Login now
rejects non-bcrypt legacy database values; users whose existing records contain
plaintext passwords must reset their password before logging in.

Password reset is rate-limited per email in-process and sets
`must_change_password` before allowing other authenticated API actions. Student
temporary passwords use the first 9 characters of the email local part;
caretaker temporary passwords use the first 13 as requested. These defaults are
predictable, and the current reset endpoint does not prove mailbox ownership or
send the generated password to that mailbox. Add an email verification step
before exposing password reset publicly; otherwise an attacker who knows a
caretaker email can reset that caretaker's password.

## Registration identity pattern

The checked-in source contains generic sample addresses, not verified student
accounts in the institute's actual format. No production database connection or
authorized account export was available, so the `bt24cs034` local-part pattern
could not be confirmed. Registration currently checks the institute domain and
enforces case-insensitive uniqueness; a stricter local-part regex needs an
authorized source confirming the institute's actual naming pattern.

## Deployment readiness follow-up

- The Google Maps API key was present in `flutter_app/ios/Runner/AppDelegate.swift`, `flutter_app/ios/Runner/Info.plist`, `flutter_app/android/gradle.properties`, and `flutter_app/web/index.html`; the initial iOS/web source was committed in `1c85b04`. It is removed from current source and supplied through Xcode/Gradle build settings; Web uses a placeholder to replace during deployment. Since it was committed and is a client key, rotate and restrict it before release.
- Historical server credentials are not safe just because current env files are ignored. Rotate the telemetry `API_SECRET_KEY`, PostgreSQL password, and the separate Compose password before going live; see `DEPLOYMENT.md`.
- The server does not use JWT signing: session tokens are random in-memory tokens. There is no `JWT_SECRET` variable to configure.
- `DATABASE_URL` is an optional supported alternative to `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME`; the Render Blueprint uses the split variables.
- Local `.env` files are ignored and are not tracked. Example env files contain placeholders only.
