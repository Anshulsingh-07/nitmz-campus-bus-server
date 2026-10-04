# ESP32 telemetry capabilities

The server accepts upstream ESP32 payload aliases (`latitude`/`longitude`, `speed_kmh`, `timestamp`, and `net_type`) at `POST /api/update-location`. It persists GPS diagnostics in `telemetry`, exposes protected `GET /api/telemetry/diagnostics` and `GET /api/telemetry/history?bus_id=5` endpoints for caretakers/admins, and provides authenticated server-sent events at `GET /api/buses/stream`. Student streams remain restricted to the student's hostel and omit hardware diagnostics.
