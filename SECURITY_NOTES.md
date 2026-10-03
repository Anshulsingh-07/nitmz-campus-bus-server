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
  accounts when the users table was empty. Seeding has been removed, and startup
  deletes the known legacy demo account addresses so existing seeded credentials
  cannot continue to work.
- Public registration previously accepted `role: caretaker` from the request.
  It now always creates a student account; caretaker accounts must be provisioned
  by a trusted process.
- `my_server/server.log` contained those demo credentials and local database
  connection details. The historical log has been redacted.

## Other findings to remediate

- `docker-compose.yml` contains a hardcoded database password. Rotate it because
  it was committed, then move it to deployment secrets/environment configuration.
- `my_server/server.js` has a fixed fallback for `API_SECRET_KEY` in development.
  Remove the fallback and rotate the key anywhere that value has been used.
- User passwords are currently stored and compared as plaintext in the backend
  (`my_server/schema.sql` and `/api/auth/register`, `/api/auth/login` in
  `my_server/server.js`). Part B should migrate storage to password hashes.
- `my_server/server.js` contains seeded demo driver names and phone numbers.
  Treat these as sample data and replace them before using a real deployment.

## Registration identity pattern

The checked-in source contains generic sample addresses, not verified student
accounts in the institute's actual format. No production database connection or
account export was available during inspection, so the `bt24cs034` local-part
pattern has not yet been confirmed against real accounts. Do not enforce a guessed
pattern until it is confirmed with an authorized account source.
