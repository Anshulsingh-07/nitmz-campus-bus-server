# Driver account and location API changes

The app already uses `google_maps_flutter` with configured Android and iOS map keys, so the lower-risk map choice is to keep that renderer and its existing `MapType` options. The backend uses Express with PostgreSQL (Supabase). Existing email accounts continue to use `/api/auth/register` and `/api/auth/login`. Driver PINs are hashed with bcrypt (cost factor 12). Driver tokens are signed HS256 JWTs and expire after 12 hours. Configure `JWT_SECRET` in the backend environment; it falls back to `API_SECRET_KEY` for existing deployments. Only one live session is allowed per driver; a second login receives HTTP 409 until the first session signs out or expires.

## Endpoints

### `GET /api/auth/driver/buses`
Returns enabled buses without an active legacy driver assignment or pending/approved mobile-driver claim:

```json
[{"busNumber":5,"route":"Hostel ↔ MBSE"}]
```

### `POST /api/auth/driver/register`
Request:

```json
{"name":"Driver Name","phone":"9876543210","pin":"123456","busNumber":5}
```
Returns HTTP 201 and `{ "status": "pending", "message": "Awaiting caretaker approval" }`. Phone is normalized to its final 10 digits and must be an Indian mobile number. Duplicate phones and buses with an active legacy driver, pending request, or approved driver return 409. No token is issued while pending.

### `POST /api/auth/driver/login`
Request `{ "phone":"9876543210", "pin":"123456" }`. Approved account response:

```json
{"token":"...","user":{"id":"drv_...","name":"Driver Name","phone":"9876543210","role":"driver","busNumber":5}}
```
Wrong phone/PIN returns 401; pending approval returns `403 {"error":"pending_approval","message":"Your account is awaiting caretaker approval"}`; rejected registrations return `403 {"error":"rejected","message":"Your registration was rejected. Contact the caretaker for details."}`; an existing session returns 409; five failed attempts trigger a 15-minute in-process lock (429 while locked).

### `POST /api/location`
Bearer token required. Request:

```json
{"busNumber":5,"lat":23.7929,"lng":92.7278,"speed":18.4,"heading":90,"accuracy":8,"status":"running","timestamp":"2026-10-01T12:00:00Z"}
```
The server loads the approved account from the authenticated token and compares `busNumber` with that account's assignment before writing telemetry or updating the bus row. A mismatch returns 403. Invalid values or accuracy worse than 50m return 400. The server writes `device_id = NULL` because the phone is the location source; speed below 1.5km/h is saved as idle. Successful updates return `{ "status":"success" }`. The bus API returns `lastUpdated` from the latest telemetry row; the app grays out locations older than 120 seconds.

### Admin / caretaker driver management
`GET /api/admin/drivers/pending` lists pending requests and `GET /api/admin/drivers/approved` lists active assignments (both return arrays containing id, name, phone, busNumber, and createdAt). `POST /api/admin/drivers/:id/approve` and `POST /api/admin/drivers/:id/reject` accept a driver id and set the account to `approved` or `rejected`; `PATCH /api/admin/drivers/:id` accepts `{ "action":"approve" }`, `{ "action":"reject" }`, `{ "action":"reassign", "busNumber":7 }`, or `{ "action":"remove" }`. Successful changes return `{ "status":"<action>" }`. These routes require the existing `admin` or `caretaker` role. Approval/reassignment checks the bus and uniqueness constraints in a transaction, updates the unique `drivers.bus_number` claim, then revokes any previous session for that account. A conflict returns 409. Remove deletes the bus display claim, marks the account removed, and revokes its active session. `POST /api/auth/logout` releases the current token and driver session lock.

## Database change

Initialization creates this PostgreSQL table and partial unique index idempotently:

```sql
CREATE TABLE driver_accounts (
  id VARCHAR(40) PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(10) NOT NULL UNIQUE,
  pin_hash VARCHAR(100) NOT NULL,
  bus_number INT NOT NULL REFERENCES buses(bus_number),
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  failed_attempts INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMP NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  approved_at TIMESTAMP NULL
);
CREATE UNIQUE INDEX driver_accounts_approved_bus_unique
  ON driver_accounts (bus_number) WHERE status IN ('pending','approved');
```

`drivers.bus_number` remains unique and represents the active display assignment. Approval/reassignment changes that row and the account's `bus_number` in one transaction. At most one approved driver account can claim a bus; pending claims also block new registration. Reassignment checks for a conflicting active driver row, clears the previous driver's row, then creates the new claim. Existing legacy bus assignments must be cleared by an administrator before a mobile-driver account can claim that bus. Driver location requests do not accept a device ID. The legacy API-key endpoint `POST /api/update-location` returns 403 if its payload names a bus with an approved phone driver, preventing the former hardware feed from replacing phone fixes.
