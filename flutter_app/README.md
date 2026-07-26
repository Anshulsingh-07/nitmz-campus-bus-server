# 🚌 Campus Bus Tracker - NIT Mizoram

A full-stack Smart Bus Tracking & Schedule Management System.

## 🛠 Tech Stack
- **Frontend**: Flutter (Web + Android)
- **Backend**: Node.js + Express
- **Database**: MySQL
- **Real-time**: REST endpoints for bus, schedule, and telemetry updates
- **IoT**: Blynk-compatible telemetry endpoint for ESP32 GPS updates

## 🔑 Login Credentials (Demo)
| Role | Email | Password |
|------|-------|----------|
| Admin (Caretaker) | admin@nitmz.ac.in | admin123 |
| Student | student@nitmz.ac.in | student123 |

## 🚌 Bus Assignment
| Hostel | Buses |
|--------|-------|
| GH1 (Girls) | Bus 1, 2, 3 |
| GH2 (Girls) | Bus 4, 22 |
| BH1 (Boys) | Bus 5-12 |
| BH2 (Boys) | Bus 13, 14, 15 |
| BH3 (Boys) | Bus 16-20 |
| BH4 (Boys) | Bus 21 |

## 📱 Features
### Student
- View buses for your hostel
- Live GPS map (Aizawl/Chaltlang area)
- Today's departure schedule
- Driver contact (one-tap call)
- Push notifications
- Bus status (Running/Maintenance/Idle)

### Admin (Caretaker)
- Full bus management
- Update daily schedules
- Send notifications to students
- Emergency alerts
- All buses live map
- Hostel-wise summary

## 🚀 Running Locally
```bash
# Backend
cd my_server
npm install
node server.js

# Frontend
cd flutter_app
flutter pub get
flutter run -d chrome
```

## 🌐 Running On Different Hosts
If the Flutter app and backend are on different machines, pass the backend IP address to the app:

```bash
# Backend machine
cd my_server
npm install
PORT=3000 HOST=0.0.0.0 node server.js

# Flutter machine
cd flutter_app
flutter pub get
flutter run -d chrome \
	--dart-define=API_HOST=<backend-ip> \
	--dart-define=API_PORT=3000 \
	--dart-define=TRACKING_HOST=<backend-ip> \
	--dart-define=TRACKING_PORT=5000
```

Replace `<backend-ip>` with the LAN IP address of the machine running the server.

## 📡 Blynk IoT Integration
Virtual Pins:
- V0: Latitude
- V1: Longitude
- V2: Bus Status
- V3: Departure Time
- V4: ETA
- V5: Notification Trigger
