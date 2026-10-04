# Deployment guide

## ROTATE THESE BEFORE GOING LIVE

Secrets were committed in Git history. Rotating files in the current tree does
not revoke values in old commits. Before production deployment:

- Replace the historical `API_SECRET_KEY` from `my_server/.env` and update any
  ESP32 sender that uses it.
- Change the PostgreSQL password exposed in `my_server/.env` and
  `docker-compose.yml`; update the hosted database and Render environment.
- Replace/restrict the Google Maps API key committed in
  `flutter_app/ios/Runner/AppDelegate.swift` and `Info.plist` in commit
  `1c85b04`. It is a client key, but has been publicly exposed and should be
  restricted to the app and required APIs.

History includes `my_server/.env` in commits `772b473` and `959565b`, the Compose
password in `772b473`, and the Maps key in `1c85b04`. History has not been
rewritten.

## 1. Prepare the database

Create a reachable PostgreSQL database (for example, with a hosted PostgreSQL
provider). Keep its host, port, database, username, and new password available.
The backend runs schema initialization and sample hostel/bus seeding during
startup; there is no separate migration command. Review/remove sample records
before production use. Create caretaker/admin accounts through a trusted,
access-controlled database process; public registration creates student
accounts only.

For local development, copy `my_server/.env.example` to `my_server/.env`, set
real local values, then run `npm install` and `npm start` from `my_server/`.
Never commit the local env file.

## 2. Deploy the backend to Render

1. Push the repository to GitHub and connect it in Render.
2. Choose **New + → Blueprint**, select the repository, and apply the root
   [`render.yaml`](render.yaml). It creates the `my_server/` Node service, runs
   `npm install` and `npm start`, and checks `GET /`.
3. In the service environment, set every value listed in
   [`my_server/.env.example`](my_server/.env.example): `API_SECRET_KEY`,
   `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `DB_SSL`, and
   `NODE_ENV`. Use a newly generated high-entropy API key and rotated hosted
   database credentials. Set `NODE_ENV=production` and `DB_SSL=true` when
   required by your provider. Render supplies `PORT`; do not hardcode it. The
   backend also supports `DATABASE_URL` instead of the split `DB_*` variables if
   you change the Blueprint accordingly.
4. Deploy. Open the service URL and confirm `GET /` returns `{"status":"ok"}`;
   `GET /api/health` also checks database connectivity. Save the service URL.

The backend currently allows CORS from `*`, acceptable for current mobile app
use. Restrict it to the deployed web frontend origin if Flutter Web is exposed
publicly.

## Password resets

The current temporary-password behavior is role-specific: students receive the
first 9 characters of their email local part, and caretakers receive the first
13. For `caretaker-gh1@nitmz.ac.in`, that temporary password is
`caretaker-gh1`; the app requires a new password immediately after sign-in.
This reset endpoint does not verify mailbox ownership or send the temporary
password, so add a verified email reset flow before making password reset
available on a public production deployment.

## 3. Build the Flutter release APK

From the repository root:

```sh
cd flutter_app
flutter build apk --release --dart-define=API_BASE_URL=https://nitmz-campus-bus-server.onrender.com
```

Replace the URL with the live Render service URL. The app reads the base URL
from `lib/config/app_config.dart`; the define overrides its production default.
For an Android emulator local server use
`--dart-define=API_BASE_URL=http://10.0.2.2:8080`; for a physical device, use a
reachable LAN address. The APK is at
`build/app/outputs/flutter-apk/app-release.apk`.

Google Maps and Mapbox credentials are client-side keys, not server secrets.
Restrict and rotate them. The iOS Google Maps key now uses the Xcode build
setting `MAPS_API_KEY`; Android uses the Gradle `MAPS_API_KEY` project property
for its manifest placeholder (locally, you can add `mapsApiKey=...` to the
ignored `android/key.properties`). The Web `index.html` contains a placeholder;
replace `YOUR_GOOGLE_MAPS_API_KEY` at web deployment/build time with a restricted
key. Do not commit the real key.

## 4. Flutter Web (optional)

`flutter_app/web/` is present, so web builds are supported:

```sh
cd flutter_app
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-SERVICE.onrender.com
```

Host `build/web/` on a static web host and allow that exact origin through CORS
before publishing it.

## If something breaks

- A Render free web service may sleep while idle; the first request after idle
  can take 30–50 seconds. Wait for it to wake, then retry.
- Check the service **Logs** in Render for startup, missing env var, or database
  and TLS errors.
- Check `GET /` for service health and `/api/health` for database reachability.
- If Flutter requests the wrong endpoint, pass the service origin without
  `/api`; the app adds `/api` itself, then rebuild with the correct define.
