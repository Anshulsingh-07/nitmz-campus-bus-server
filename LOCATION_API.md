# Driver location API

The app authenticates drivers against the existing `drivers` row joined to its assigned bus. Drivers do not register, select a bus, or wait for approval. A caretaker sets or resets the PIN from **Bus Management → Edit Driver + Mobile**. Enter a 6-digit PIN in the write-only PIN field and save. The server stores a bcrypt hash; it never returns the PIN or its hash. Repeat for each driver. A blank PIN field leaves the existing PIN unchanged.

## Driver login

`POST /api/auth/driver-login`

Request:

```json
{"phone":"9862369186","pin":"583104"}
```

Success (`200`):

```json
{"token":"<bearer-token>","user":{"id":"drv5","name":"Chhuanga","phone":"9862369186","busNumber":5,"role":"driver"}}
```

An unknown phone returns `404` with `Mobile number not recognized`; a known driver with a wrong PIN returns `401` with `Incorrect PIN`. Five failed attempts for one phone trigger a 15-minute lock (`429`). Disabled drivers and disabled buses cannot log in. The driver token is tied to the returned `busNumber` and expires after 12 hours or logout.

On app restart, `GET /api/auth/driver/me` with the bearer token revalidates the driver and returns `{ "user": { "id", "name", "phone", "busNumber", "role": "driver" } }`.

## Location update

`POST /api/location` with `Authorization: Bearer <token>`.

Request:

```json
{
  "busNumber": 5,
  "lat": 23.7929,
  "lng": 92.7278,
  "speed": 18.4,
  "heading": 90,
  "accuracy": 8,
  "timestamp": "2026-10-02T08:30:00.000Z"
}
```

`speed` is km/h. `heading` is degrees clockwise from north and may be `null` if the device has no valid bearing. `accuracy` is metres. The app sends at most one fix every 2.5 seconds, skips fixes less than 5m apart, and sends a heartbeat at least every 12 seconds. During network loss it stores at most 200 fixes locally and retries them in order.

Success (`200`):

```json
{"ok":true}
```

The server rejects a bus number different from the bus bound to the token (`403`), bad coordinates or fixes worse than 50m accuracy (`400`), and expired tokens (`401`). Stale queued timestamps are acknowledged with `{"ok":true,"stale":true}` without moving the bus backwards. Sending `"status":"idle"` marks the end of a trip.

## Speed and heading

For each bus, the server remembers its last accepted phone fix, restoring the previous phone fix from telemetry after a server restart. On the first phone fix it uses the device speed as the initial baseline. Later it computes speed from haversine distance and elapsed time. If the device's reported speed differs by more than roughly a factor of two (with a 2 km/h tolerance at low speed), the computed speed is used. The chosen value is smoothed with an exponential moving average: 70% previous smoothed speed and 30% new speed. Speeds above the plausible 180 km/h computed-fix bound do not replace the client value. If the device does not send a valid heading, the server computes the bearing from the last fix to the new fix. Status is `running` above 1.5 km/h, otherwise `idle`.

The accepted fix is written to telemetry and the bus row in one PostgreSQL transaction. After commit, the server immediately publishes a `live_update` SSE event. PostgreSQL pool size defaults to 20 (`PG_POOL_MAX` can override it); that is sized above the roughly 8 updates/second expected from 22 buses sending every 2.5–3 seconds. Actual headroom still depends on the deployed PostgreSQL/Supabase connection limit and latency.

## Student bus stream

`GET /api/buses/stream` with a student, caretaker, or admin bearer token returns Server-Sent Events. Students receive only buses assigned to their hostel. The first `data:` event is the current fleet (an array); later events are one-item arrays, one per changed bus. The relevant bus fields are:

```json
{
  "busNumber": 5,
  "busId": "5",
  "assigned_hostel": "BH1",
  "latitude": 23.7929,
  "longitude": 92.7278,
  "lat": 23.7929,
  "lng": 92.7278,
  "speed": 18.4,
  "heading": 90,
  "status": "running",
  "hasFix": true,
  "timestamp": "2026-10-02T08:30:00.000Z",
  "lastUpdated": "2026-10-02T08:30:00.000Z"
}
```

Student updates omit hardware diagnostics such as satellite count and HDOP. `GET /api/buses` remains the source of bus metadata including the read-only `driver: { name, phone, busNumber, isActive }` object.
