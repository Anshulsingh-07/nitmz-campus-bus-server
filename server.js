const express = require('express');
const crypto = require('crypto');
const EventEmitter = require('events');
const bcrypt = require('bcryptjs');
const { Pool } = require('pg');
require('dotenv').config();

if (process.env.NODE_ENV === 'production' && !process.env.API_SECRET_KEY) {
    throw new Error('API_SECRET_KEY must be configured in production');
}

const app = express();
const telemetryEmitter = new EventEmitter();
telemetryEmitter.setMaxListeners(0);
const port = Number(process.env.PORT || 8080);
const API_SECRET_KEY = process.env.API_SECRET_KEY || 'BUSTRACKESP1SECRETKEY';

const DB_HOST = process.env.DB_HOST || '127.0.0.1';
const DB_PORT = Number(process.env.DB_PORT || 5432);
const DB_USER = process.env.DB_USER || 'root';
const DB_PASSWORD = process.env.DB_PASSWORD || '';
const DB_NAME = process.env.DB_NAME || 'campus_bus_tracker';

let pool;

const hostelsSeed = [
    { id: 'GH1', name: 'GH1', type: 'Girls', fullName: "Girls' Hostel 1" },
    { id: 'GH2', name: 'GH2', type: 'Girls', fullName: "Girls' Hostel 2" },
    { id: 'BH1', name: 'BH1', type: 'Boys', fullName: "Boys' Hostel 1" },
    { id: 'BH2', name: 'BH2', type: 'Boys', fullName: "Boys' Hostel 2" },
    { id: 'BH3', name: 'BH3', type: 'Boys', fullName: "Boys' Hostel 3" },
    { id: 'BH4', name: 'BH4', type: 'Boys', fullName: "Boys' Hostel 4" },
];

const usersSeed = [
    { id: 'caretaker-gh1', name: 'GH1 Caretaker', email: 'caretaker-gh1@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'GH1' },
    { id: 'caretaker-gh2', name: 'GH2 Caretaker', email: 'caretaker-gh2@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'GH2' },
    { id: 'caretaker-bh1', name: 'BH1 Caretaker', email: 'caretaker-bh1@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'BH1' },
    { id: 'caretaker-bh2', name: 'BH2 Caretaker', email: 'caretaker-bh2@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'BH2' },
    { id: 'caretaker-bh3', name: 'BH3 Caretaker', email: 'caretaker-bh3@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'BH3' },
    { id: 'caretaker-bh4', name: 'BH4 Caretaker', email: 'caretaker-bh4@nitmz.ac.in', password: 'caretaker123', role: 'caretaker', hostelId: 'BH4' },
    { id: 'student-bh1', name: 'Anshul Student', email: 'student@nitmz.ac.in', password: 'student123', role: 'student', hostelId: 'BH1' },
];

const busesSeed = [
    [1, 'GH1', 'Pa Hlutea', '9436168711', 23.7285, 92.7180, 'idle', '8:30 AM', '1:30 PM'],
    [2, 'GH1', 'Pu Stephen', '8787778119', 23.7260, 92.7165, 'running', '9:15 AM', '4:30 PM'],
    [3, 'GH1', 'Mawizuala', '8131811729', 23.7290, 92.7200, 'idle', '8:30 AM', '5:30 PM'],
    [4, 'GH2', 'Hruaia', '6909101103', 23.7240, 92.7150, 'running', '8:15 AM', '4:30 PM'],
    [5, 'BH1', 'Chhuanga', '9862369186', 23.7275, 92.7185, 'running', '8:15 AM', '5:30 PM'],
    [6, 'BH1', 'Pa Dina', '9615408299', 23.7265, 92.7170, 'idle', '8:15 AM', '7:00 PM'],
    [7, 'BH1', 'Vk-a', '7005367693', 23.7280, 92.7195, 'running', '8:15 PM', '5:30 PM'],
    [8, 'BH1', 'Dama', '7005364878', 23.7255, 92.7160, 'idle', '6:30 AM', '12:30 PM', 'IoN Digital Centre Mualpui'],
    [9, 'BH1', 'Mala', '6009425695', 23.7295, 92.7205, 'maintenance', '1:00 PM', '4:30 PM'],
    [10, 'BH1', 'Rinkima', '7005616947', 23.7270, 92.7175, 'idle', '9:15 AM', '1:30 PM'],
    [11, 'BH1', 'Pa Dika', '6909470121', 23.7250, 92.7155, 'running', '9:15 AM', '1:30 PM'],
    [12, 'BH1', 'Ramtea', '8729985255', 23.7285, 92.7190, 'idle', '10:15 AM', '2:30 PM'],
    [13, 'BH2', 'Lalrammawia', '9862411234', 23.7260, 92.7165, 'running', '9:20 AM', '2:00 PM'],
    [14, 'BH2', 'Vanlalruata', '8014567890', 23.7245, 92.7148, 'idle', '8:20 AM', '3:20 PM'],
    [15, 'BH2', 'Zohmingliana', '7005223344', 23.7300, 92.7210, 'running', '8:20 AM', '11:15 AM'],
    [16, 'BH3', 'Lalduhawma', '9856112233', 23.7230, 92.7140, 'idle', '8:00 AM', '4:00 PM'],
    [17, 'BH3', 'Vanlalngaia', '6009334455', 23.7315, 92.7215, 'running', '9:00 AM', '5:00 PM'],
    [18, 'BH3', 'Hmingthansanga', '7005556677', 23.7240, 92.7155, 'idle', '8:30 AM', '3:30 PM'],
    [19, 'BH3', 'Lalremruata', '8259667788', 23.7305, 92.7205, 'idle', '9:30 AM', '4:30 PM'],
    [20, 'BH3', 'Thangmawia', '9612778899', 23.7235, 92.7145, 'running', '10:00 AM', '2:00 PM'],
    [21, 'BH4', 'Kaptluanga', '9862990011', 23.7320, 92.7220, 'idle', '8:45 AM', '5:00 PM'],
    [22, 'GH2', 'Saka', '9378074359', 23.7245, 92.7152, 'running', '8:25 AM', '5:30 PM'],
];

const notificationsSeed = [
    ['n1', 'Bus 5 Departure Alert', 'Bus 5 will depart from BH1 at 8:15 AM. Please be ready!', 'departure', 5, 'BH1', false],
    ['n2', 'Bus 7 Schedule Update', 'Bus 7 schedule updated. From Hostel: 8:15 PM, From MBSE: 5:30 PM', 'general', 7, 'BH1', false],
    ['n3', 'Bus 2 Arriving Soon', 'Bus 2 (GH1) is 1 km away from hostel. ETA: 5 minutes!', 'arrival', 2, 'GH1', true],
    ['n4', 'Bus 9 Maintenance', 'Bus 9 is under maintenance today. Please use alternate buses.', 'delay', 9, 'BH1', true],
];

const sessions = new Map();
const driverLoginFailures = new Map();
const driverLastFixes = new Map();

const today = () => new Date().toISOString().slice(0, 10);
const uid = (prefix) => `${prefix}${crypto.randomBytes(6).toString('hex')}`;

app.use(express.json());
app.use((req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-api-key');
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
    if (req.method === 'OPTIONS') return res.sendStatus(204);
    return next();
});

async function q(sql, params = []) {
    // convert '?' placeholders to $1, $2, ... for pg
    let idx = 0;
    const text = sql.replace(/\?/g, () => `$${++idx}`);
    const res = await pool.query(text, params);
    return res.rows;
}

function publicUser(row) {
    return {
        id: row.id,
        name: row.name,
        email: row.email,
        role: row.role,
        hostelId: row.hostel_id,
    };
}

function mapSchedule(row) {
    if (!row.schedule_id) return null;
    return {
        _id: row.schedule_id,
        busNumber: row.bus_number,
        date: row.schedule_date,
        fromHostelTime: row.from_hostel_time,
        fromMBSETime: row.from_mbse_time,
        specialNote: row.special_note || '',
        updatedBy: row.updated_by || '',
    };
}

function mapBus(row) {
    return {
        busNumber: row.bus_number,
        assignedHostel: row.assigned_hostel,
        status: row.status,
        latitude: Number(row.latitude),
        longitude: Number(row.longitude),
        speed: Number(row.speed),
        isEnabled: !!row.is_enabled,
        route: row.route || 'Hostel ↔ MBSE',
        lastUpdated: row.last_updated ? (row.last_updated.toISOString?.() ?? row.last_updated) : null,
        driver: row.driver_id
            ? {
                _id: row.driver_id,
                name: row.driver_name,
                phone: row.driver_phone,
                busNumber: row.bus_number,
                isActive: !!row.driver_is_active,
            }
            : null,
        schedule: mapSchedule(row),
    };
}

function mapLiveBus(row) {
    return {
        busNumber: row.bus_number,
        status: row.status,
        lat: row.lat != null ? Number(row.lat) : Number(row.latitude),
        lng: row.lng != null ? Number(row.lng) : Number(row.longitude),
        speed: Number(row.speed || 0),
        route: row.route || 'Hostel ↔ MBSE',
        hostel: row.assigned_hostel,
        hasFix: row.has_fix ?? (row.lat != null && row.lng != null),
        satellites: row.satellites != null ? Number(row.satellites) : null,
        hdop: row.hdop != null ? Number(row.hdop) : null,
        netType: row.net_type || 'API',
        lastUpdated: row.received_at || null,
    };
}

function normalizeTelemetry(body = {}) {
    const rawBusId = body.bus_id ?? body.bus_number ?? body.busId ?? body.busNo ?? body.bus ?? null;
    return {
        deviceId: body.device_id || body.deviceId || null,
        busId: rawBusId === null ? null : String(rawBusId),
        lat: Number(body.lat ?? body.latitude ?? body.lat_deg),
        lng: Number(body.lng ?? body.longitude ?? body.lng_deg ?? body.long),
        speed: Number(body.speed ?? body.speed_kmh ?? body.spd ?? 0),
        accuracy: Number(body.accuracy ?? body.hdop ?? 1),
        hasFix: body.has_fix ?? null,
        satellites: Number(body.satellites ?? 0),
        hdop: Number(body.hdop ?? body.accuracy ?? 99.9),
        netType: body.net_type || body.netType || 'unknown',
        timestamp: body.ts ?? body.timestamp ?? null,
        status: body.status || 'idle',
    };
}

function haversineKm(a, b) {
    const radians = (degrees) => degrees * Math.PI / 180;
    const dLat = radians(b.lat - a.lat);
    const dLng = radians(b.lng - a.lng);
    const value = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a.lat)) * Math.cos(radians(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 6371 * 2 * Math.atan2(Math.sqrt(value), Math.sqrt(1 - value));
}

function bearingDegrees(a, b) {
    const radians = (degrees) => degrees * Math.PI / 180;
    const lat1 = radians(a.lat);
    const lat2 = radians(b.lat);
    const lngDelta = radians(b.lng - a.lng);
    const y = Math.sin(lngDelta) * Math.cos(lat2);
    const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(lngDelta);
    return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
}

function requireAuth(req, res, allowedRoles = null) {
    const header = req.header('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token || !sessions.has(token) || sessions.get(token).expiresAt < Date.now()) {
        if (token && sessions.has(token)) sessions.delete(token);
        res.status(401).json({ error: 'Unauthorized' });
        return null;
    }

    const session = sessions.get(token);
    if (allowedRoles && !allowedRoles.includes(session.role)) {
        res.status(403).json({ error: 'Forbidden' });
        return null;
    }

    return { token, ...session };
}

function createToken(user) {
    const expiresAt = Date.now() + 24 * 30 * 60 * 60 * 1000;
    const token = crypto.randomBytes(24).toString('hex');
    sessions.set(token, {
        userId: user.id,
        email: user.email,
        role: user.role,
        hostelId: user.hostel_id,
        phone: user.phone,
        busNumber: user.bus_number,
        expiresAt,
    });
    return token;
}

const BUS_SELECT = `
SELECT
  b.bus_number,
  b.assigned_hostel,
  b.status,
  b.latitude,
  b.longitude,
  b.speed,
  b.is_enabled,
  b.route,
  live.last_updated,
  d.id AS driver_id,
  d.name AS driver_name,
  d.phone AS driver_phone,
  d.is_active AS driver_is_active,
  s.id AS schedule_id,
  s.date AS schedule_date,
  s.from_hostel_time,
  s.from_mbse_time,
  s.special_note,
  s.updated_by
FROM buses b
LEFT JOIN drivers d ON d.bus_number = b.bus_number AND d.is_active = true
LEFT JOIN (
  SELECT DISTINCT ON (bus_id) bus_id, received_at AS last_updated
  FROM telemetry WHERE bus_id IS NOT NULL
  ORDER BY bus_id, received_at DESC
) live ON live.bus_id = CAST(b.bus_number AS TEXT)
LEFT JOIN (
  SELECT s1.*
  FROM schedules s1
  JOIN (
    SELECT bus_number, MAX(updated_at) AS max_updated
    FROM schedules
    GROUP BY bus_number
  ) s2 ON s1.bus_number = s2.bus_number AND s1.updated_at = s2.max_updated
) s ON s.bus_number = b.bus_number
`;

async function fetchBusByNumber(busNumber) {
    const rows = await q(`${BUS_SELECT} WHERE b.bus_number = ?`, [busNumber]);
    return rows.length ? mapBus(rows[0]) : null;
}

async function assertCaretakerAccess(busNumber, auth) {
    const busRows = await q('SELECT bus_number, assigned_hostel FROM buses WHERE bus_number = ? LIMIT 1', [busNumber]);
    if (!busRows.length) {
        return { ok: false, code: 404, message: 'Bus not found' };
    }
    if (auth.role === 'caretaker' && auth.hostelId && busRows[0].assigned_hostel !== auth.hostelId) {
        return { ok: false, code: 403, message: 'Caretaker can only update own hostel buses' };
    }
    return { ok: true, bus: busRows[0] };
}

async function initializeDatabase() {
    // Create a pg Pool connected to Supabase/Postgres
    const poolConfig = process.env.DATABASE_URL
        ? {
            connectionString: process.env.DATABASE_URL,
            ssl: { rejectUnauthorized: false },
            max: Number(process.env.PG_POOL_MAX || 20),
            idleTimeoutMillis: 30000,
        }
        : {
            host: DB_HOST,
            port: DB_PORT,
            user: DB_USER,
            password: DB_PASSWORD,
            database: DB_NAME,
            max: Number(process.env.PG_POOL_MAX || 20),
            idleTimeoutMillis: 30000,
            ssl: process.env.DB_SSL === 'true' || DB_HOST.includes('supabase') ? { rejectUnauthorized: false } : false,
        };
    pool = new Pool(poolConfig);

    // Create tables (Postgres-compatible)
    await q(`
CREATE TABLE IF NOT EXISTS hostels (
  id VARCHAR(10) PRIMARY KEY,
  name VARCHAR(20) NOT NULL,
  type VARCHAR(20) NOT NULL,
  full_name VARCHAR(100) NOT NULL
);
`);

    await q(`
CREATE TABLE IF NOT EXISTS users (
  id VARCHAR(40) PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(120) NOT NULL UNIQUE,
  password VARCHAR(120) NOT NULL,
  role VARCHAR(20) NOT NULL,
  hostel_id VARCHAR(10) NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (hostel_id) REFERENCES hostels(id) ON DELETE SET NULL
);
`);

    await q(`
CREATE TABLE IF NOT EXISTS buses (
  bus_number INT PRIMARY KEY,
  assigned_hostel VARCHAR(10) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'idle',
  latitude NUMERIC(10,6) NOT NULL,
  longitude NUMERIC(10,6) NOT NULL,
  speed NUMERIC(8,2) NOT NULL DEFAULT 0,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  route VARCHAR(120) NOT NULL DEFAULT 'Hostel ↔ MBSE',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (assigned_hostel) REFERENCES hostels(id)
);
`);

    await q(`
CREATE TABLE IF NOT EXISTS drivers (
  id VARCHAR(40) PRIMARY KEY,
  bus_number INT NOT NULL UNIQUE,
    name VARCHAR(120) NULL,
  phone VARCHAR(30) NULL,
  pin_hash VARCHAR(100) NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  FOREIGN KEY (bus_number) REFERENCES buses(bus_number) ON DELETE CASCADE
);
`);
    await q('ALTER TABLE drivers ADD COLUMN IF NOT EXISTS pin_hash VARCHAR(100) NULL');
    await q('DROP INDEX IF EXISTS drivers_active_phone_unique');
    await q(`
CREATE TABLE IF NOT EXISTS notifications (
  id VARCHAR(40) PRIMARY KEY,
  title VARCHAR(160) NOT NULL,
  message TEXT NOT NULL,
  type VARCHAR(30) NOT NULL,
  bus_number INT NULL,
  target_hostel VARCHAR(10) NULL,
  sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  is_read BOOLEAN NOT NULL DEFAULT false,
  sent_by VARCHAR(120) NULL,
  FOREIGN KEY (target_hostel) REFERENCES hostels(id) ON DELETE SET NULL
);
`);

    await q(`
CREATE TABLE IF NOT EXISTS telemetry (
  id SERIAL PRIMARY KEY,
  device_id VARCHAR(60) NULL,
  bus_id VARCHAR(40) NULL,
  lat NUMERIC(10,6) NOT NULL,
  lng NUMERIC(10,6) NOT NULL,
  speed NUMERIC(8,2) NOT NULL DEFAULT 0,
  accuracy NUMERIC(8,2) NOT NULL DEFAULT 1.0,
  heading NUMERIC(6,2) NOT NULL DEFAULT 0,
  ts VARCHAR(64) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'idle',
  received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
`);
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS has_fix BOOLEAN DEFAULT false');
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS satellites INT DEFAULT 0');
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS hdop NUMERIC(6,2) DEFAULT 99.9');
    await q("ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS net_type VARCHAR(20) DEFAULT 'unknown'");
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS heading NUMERIC(6,2) NOT NULL DEFAULT 0');

    const [hostelCountRow] = await q('SELECT COUNT(*) AS count FROM hostels');
    const hostelCount = hostelCountRow ? Number(hostelCountRow.count) : 0;
    if (hostelCount === 0) {
        for (const hostel of hostelsSeed) {
            await q('INSERT INTO hostels (id, name, type, full_name) VALUES ($1, $2, $3, $4)', [
                hostel.id,
                hostel.name,
                hostel.type,
                hostel.fullName,
            ]);
        }
    }

    const [userCountRow] = await q('SELECT COUNT(*) AS count FROM users');
    const userCount = userCountRow ? Number(userCountRow.count) : 0;
    if (userCount === 0) {
        for (const user of usersSeed) {
            await q(
                'INSERT INTO users (id, name, email, password, role, hostel_id) VALUES ($1, $2, $3, $4, $5, $6)',
                [user.id, user.name, user.email, user.password, user.role, user.hostelId]
            );
        }
    }

    const [busCountRow] = await q('SELECT COUNT(*) AS count FROM buses');
    const busCount = busCountRow ? Number(busCountRow.count) : 0;
    if (busCount === 0) {
        for (const [busNumber, assignedHostel, driverName, phone, latitude, longitude, status, fromHostelTime, fromMBSETime, specialNote = ''] of busesSeed) {
            await q(
                'INSERT INTO buses (bus_number, assigned_hostel, status, latitude, longitude, speed, is_enabled, route) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
                [busNumber, assignedHostel, status, latitude, longitude, status === 'running' ? 25 : 0, true, 'Hostel ↔ MBSE']
            );
            await q('INSERT INTO drivers (id, bus_number, name, phone, is_active) VALUES ($1, $2, $3, $4, $5)', [
                `drv${busNumber}`,
                busNumber,
                driverName,
                phone,
                true,
            ]);
            await q(
                'INSERT INTO schedules (id, bus_number, date, from_hostel_time, from_mbse_time, special_note, updated_by) VALUES ($1, $2, $3, $4, $5, $6, $7)',
                [`sch${busNumber}`, busNumber, today(), fromHostelTime, fromMBSETime, specialNote, 'caretaker-gh1@nitmz.ac.in']
            );
        }
    }

    const [notifCountRow] = await q('SELECT COUNT(*) AS count FROM notifications');
    const notifCount = notifCountRow ? Number(notifCountRow.count) : 0;
    if (notifCount === 0) {
        for (const [id, title, message, type, busNumber, targetHostel, isRead] of notificationsSeed) {
            await q(
                'INSERT INTO notifications (id, title, message, type, bus_number, target_hostel, is_read, sent_by) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
                [id, title, message, type, busNumber, targetHostel, !!isRead, 'seed']
            );
        }
    }

    const [telemetryCountRow] = await q('SELECT COUNT(*) AS count FROM telemetry');
    const telemetryCount = telemetryCountRow ? Number(telemetryCountRow.count) : 0;
    if (telemetryCount === 0) {
        await q(
            'INSERT INTO telemetry (device_id, bus_id, lat, lng, speed, accuracy, ts, status) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)',
            ['ESP32-1', '5', 23.7271, 92.7176, 0, 1.0, null, 'idle']
        );
    }
}

app.get('/', (_req, res) => {
    res.json({ status: 'ok', message: 'Campus Bus Tracker API running (PostgreSQL)' });
});

app.get('/api/health', async (_req, res) => {
    try {
        const [[hostels], [buses], [notifications]] = await Promise.all([
            q('SELECT COUNT(*) AS count FROM hostels'),
            q('SELECT COUNT(*) AS count FROM buses'),
            q('SELECT COUNT(*) AS count FROM notifications'),
        ]);
        res.json({ status: 'ok', hostels: hostels.count, buses: buses.count, notifications: notifications.count });
    } catch (error) {
        res.status(500).json({ status: 'error', message: error.message });
    }
});

app.get('/api/hostels', async (_req, res) => {
    try {
        const rows = await q('SELECT id, name, type, full_name AS fullName FROM hostels ORDER BY id');
        res.json({ status: 'success', data: rows });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.post('/api/auth/register', async (req, res) => {
    try {
        const { name, email, password, hostelId, role } = req.body || {};
        if (!name || !email || !password) {
            return res.status(400).json({ error: 'name, email, and password are required' });
        }
        if (!String(email).toLowerCase().endsWith('@nitmz.ac.in')) {
            return res.status(400).json({ error: 'Only @nitmz.ac.in emails are allowed' });
        }

        const existing = await q('SELECT id FROM users WHERE email = ?', [email]);
        if (existing.length > 0) {
            return res.status(409).json({ error: 'Email already registered' });
        }

        const user = {
            id: uid('usr_'),
            name,
            email,
            password,
            role: role === 'caretaker' ? 'caretaker' : 'student',
            hostel_id: hostelId || 'BH1',
        };

        await q(
            'INSERT INTO users (id, name, email, password, role, hostel_id) VALUES (?, ?, ?, ?, ?, ?)',
            [user.id, user.name, user.email, user.password, user.role, user.hostel_id]
        );

        const token = createToken(user);
        return res.json({ token, user: publicUser(user) });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/auth/logout', (req, res) => {
    const auth = requireAuth(req, res); if (!auth) return;
    sessions.delete(auth.token);
    return res.json({ status: 'success' });
});

app.get('/api/buses/live', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = auth.role === 'student' ? auth.hostelId : (req.query.hostel || null);
        const where = hostel ? 'WHERE b.assigned_hostel = ?' : '';
        const rows = await q(
            `
            SELECT
                b.bus_number,
                b.assigned_hostel,
                b.status,
                b.latitude,
                b.longitude,
                b.speed,
                b.route,
                t.lat,
                t.lng,
                t.accuracy,
                t.hdop,
                t.has_fix,
                t.satellites,
                t.net_type,
                t.status AS telemetry_status,
                t.received_at
            FROM buses b
            LEFT JOIN LATERAL (
                SELECT bus_id, lat, lng, accuracy, has_fix, satellites, hdop, net_type, status, received_at
                FROM telemetry
                WHERE regexp_replace(bus_id, '[^0-9]', '', 'g') = b.bus_number::text
                ORDER BY received_at DESC, id DESC
                LIMIT 1
            ) t ON true
            ${where}
            ORDER BY b.bus_number
            `,
            hostel ? [hostel] : []
        );

        return res.json({
            status: 'success',
            data: rows.map((row) => ({
                ...mapLiveBus(row),
                status: row.telemetry_status || row.status,
            })),
        });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/buses/stream', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = auth.role === 'student' ? auth.hostelId : null;
        const rows = await q(`
            SELECT b.bus_number, b.assigned_hostel, b.status, b.latitude, b.longitude, b.speed, b.route,
                   t.lat, t.lng, t.heading, t.has_fix, t.satellites, t.hdop, t.net_type, t.status AS telemetry_status, t.received_at
            FROM buses b
            LEFT JOIN LATERAL (
                SELECT bus_id, lat, lng, heading, has_fix, satellites, hdop, net_type, status, received_at
                FROM telemetry
                WHERE regexp_replace(bus_id, '[^0-9]', '', 'g') = b.bus_number::text
                ORDER BY received_at DESC, id DESC
                LIMIT 1
            ) t ON true
            WHERE b.is_enabled = true AND ($1::text IS NULL OR LOWER(b.assigned_hostel) = LOWER($1))
            ORDER BY b.bus_number
        `, [hostel || null]);

        const initialData = rows.map((row) => {
            const item = {
                bus_number: row.bus_number,
                busNumber: row.bus_number,
                status: row.telemetry_status || row.status,
                lat: row.lat == null ? Number(row.latitude) : Number(row.lat),
                lng: row.lng == null ? Number(row.longitude) : Number(row.lng),
                latitude: row.lat == null ? Number(row.latitude) : Number(row.lat),
                longitude: row.lng == null ? Number(row.longitude) : Number(row.lng),
                heading: Number(row.heading || 0),
                speed: Number(row.speed || 0),
                route: row.route,
                hostel: row.assigned_hostel,
                assigned_hostel: row.assigned_hostel,
                hasFix: row.has_fix ?? (row.lat != null && row.lng != null),
                lastUpdated: row.received_at || null,
                timestamp: row.received_at || null,
            };
            if (auth.role !== 'student') {
                item.satellites = row.satellites ?? 0;
                item.hdop = Number(row.hdop ?? row.accuracy ?? 99.9);
                item.netType = row.net_type || 'unknown';
            }
            return item;
        });

        res.status(200);
        res.setHeader('Content-Type', 'text/event-stream');
        res.setHeader('Cache-Control', 'no-cache, no-transform');
        res.setHeader('Connection', 'keep-alive');
        res.flushHeaders?.();
        res.write(`data: ${JSON.stringify(initialData)}\n\n`);

        const onUpdate = (data) => {
            if (auth.role === 'student' && (!auth.hostelId || auth.hostelId.toUpperCase() !== String(data.assigned_hostel || '').toUpperCase())) return;
            const eventData = { ...data };
            if (auth.role === 'student') {
                delete eventData.satellites;
                delete eventData.hdop;
                delete eventData.net_type;
                delete eventData.netType;
            }
            if (res.writable) res.write(`data: ${JSON.stringify([eventData])}\n\n`);
        };
        const heartbeat = setInterval(() => {
            if (res.writable) res.write(': keep-alive\n\n');
        }, 25000);
        telemetryEmitter.on('live_update', onUpdate);
        req.on('close', () => {
            clearInterval(heartbeat);
            telemetryEmitter.removeListener('live_update', onUpdate);
        });
    } catch (error) {
        if (!res.headersSent) return res.status(500).json({ error: error.message });
        res.end();
    }
});

app.get('/api/telemetry/diagnostics', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;
    try {
        const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 200);
        const values = [];
        let filter = '';
        if (req.query.bus_id) {
            const busNumber = String(req.query.bus_id).replace(/[^0-9]/g, '');
            if (!busNumber) return res.status(400).json({ error: 'bus_id must include a bus number' });
            values.push(busNumber);
            filter += ` AND regexp_replace(t.bus_id, '[^0-9]', '', 'g') = $${values.length}`;
        }
        if (auth.role === 'caretaker') {
            values.push(auth.hostelId || '');
            filter += ` AND b.assigned_hostel = $${values.length}`;
        }
        values.push(limit);
        const rows = await pool.query(`
            SELECT t.id, t.device_id, t.bus_id, t.lat, t.lng, t.speed, t.accuracy, t.has_fix,
                   t.satellites, t.hdop, t.net_type, t.ts, t.status, t.received_at
            FROM telemetry t
            LEFT JOIN buses b ON regexp_replace(t.bus_id, '[^0-9]', '', 'g') = b.bus_number::text
            WHERE true ${filter}
            ORDER BY t.received_at DESC, t.id DESC
            LIMIT $${values.length}
        `, values);
        const data = rows.rows.map((row) => ({
            id: row.id,
            deviceId: row.device_id,
            busId: row.bus_id,
            lat: Number(row.lat),
            lng: Number(row.lng),
            speed: Number(row.speed || 0),
            accuracy: Number(row.accuracy || 1),
            hasFix: row.has_fix ?? false,
            satellites: row.satellites ?? 0,
            hdop: Number(row.hdop ?? 99.9),
            netType: row.net_type || 'unknown',
            timestamp: row.ts,
            status: row.status,
            receivedAt: row.received_at,
        }));
        const average = (list, key) => list.length ? Math.round(list.reduce((sum, item) => sum + item[key], 0) / list.length * 10) / 10 : 0;
        return res.json({
            status: 'success',
            summary: {
                totalPackets: data.length,
                fixRate: data.length ? `${Math.round(data.filter((item) => item.hasFix).length / data.length * 100)}%` : '0%',
                avgSatellites: average(data, 'satellites'),
                avgHdop: data.length ? average(data, 'hdop') : 99.9,
                latestPacket: data[0] || null,
            },
            data,
        });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/telemetry/history', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;
    const busId = String(req.query.bus_id || '').replace(/[^0-9]/g, '');
    if (!busId) return res.status(400).json({ error: 'bus_id must include a bus number' });
    const end = req.query.end_time ? new Date(String(req.query.end_time)) : new Date();
    const start = req.query.start_time ? new Date(String(req.query.start_time)) : new Date(end.getTime() - 24 * 60 * 60 * 1000);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || start > end) {
        return res.status(400).json({ error: 'Invalid start_time or end_time' });
    }
    try {
        const values = [busId, start.toISOString(), end.toISOString()];
        let hostelFilter = '';
        if (auth.role === 'caretaker') {
            values.push(auth.hostelId || '');
            hostelFilter = ` AND b.assigned_hostel = $${values.length}`;
        }
        const rows = await pool.query(`
            SELECT t.id, t.bus_id AS "busId", t.lat, t.lng, t.speed, t.ts, t.status, t.received_at AS "receivedAt"
            FROM telemetry t
            LEFT JOIN buses b ON regexp_replace(t.bus_id, '[^0-9]', '', 'g') = b.bus_number::text
            WHERE regexp_replace(t.bus_id, '[^0-9]', '', 'g') = $1 AND t.received_at >= $2 AND t.received_at <= $3 ${hostelFilter}
            ORDER BY t.received_at ASC, t.id ASC
        `, values);
        return res.json({ status: 'success', data: rows.rows.map((row) => ({
            ...row,
            lat: Number(row.lat),
            lng: Number(row.lng),
            speed: Number(row.speed || 0),
        })) });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/auth/login', async (req, res) => {
    try {
        const { email, password } = req.body || {};
        const rows = await q('SELECT id, name, email, role, hostel_id, password FROM users WHERE email = ? LIMIT 1', [email || '']);
        if (rows.length === 0 || rows[0].password !== password) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        const user = rows[0];
        const token = createToken(user);
        return res.json({ token, user: publicUser(user) });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/auth/driver-login', async (req, res) => {
    const phone = String(req.body?.phone || '').replace(/\D/g, '').slice(-10);
    const pin = String(req.body?.pin || '');
    if (!/^[6-9]\d{9}$/.test(phone) || !/^\d{6}$/.test(pin)) {
        return res.status(400).json({ error: 'Enter a valid mobile number and 6-digit PIN' });
    }
    const now = Date.now();
    let attempts = driverLoginFailures.get(phone);
    if (attempts?.lockedUntil > now) return res.status(429).json({ error: 'Too many attempts. Try again in 15 minutes.' });
    if (attempts?.lockedUntil && attempts.lockedUntil <= now) {
        driverLoginFailures.delete(phone);
        attempts = null;
    }

    try {
        const rows = await q(`
            SELECT d.id, d.name, d.phone, d.bus_number, d.pin_hash, d.is_active, b.is_enabled
            FROM drivers d JOIN buses b ON b.bus_number = d.bus_number
            WHERE regexp_replace(d.phone, '[^0-9]', '', 'g') LIKE ? AND d.is_active = true
            ORDER BY d.bus_number LIMIT 1
        `, [`%${phone}`]);
        const driver = rows[0];
        const pinMatches = driver?.pin_hash ? await bcrypt.compare(pin, driver.pin_hash) : false;
        if (!driver || !driver.is_enabled || !pinMatches) {
            const failures = (attempts?.count || 0) + 1;
            driverLoginFailures.set(phone, { count: failures, lockedUntil: failures >= 5 ? now + 15 * 60 * 1000 : 0 });
            return res.status(driver ? 401 : 404).json({ error: driver ? 'Incorrect PIN' : 'Mobile number not recognized' });
        }
        driverLoginFailures.delete(phone);
        const user = { id: driver.id, name: driver.name || 'Driver', phone: driver.phone, bus_number: driver.bus_number, role: 'driver' };
        const token = createToken(user);
        return res.json({ token, user: { id: user.id, name: user.name, phone: user.phone, busNumber: user.bus_number, role: 'driver' } });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/auth/driver/me', async (req, res) => {
    const auth = requireAuth(req, res, ['driver']);
    if (!auth) return;
    try {
        const rows = await q(`SELECT d.id, d.name, d.phone, d.bus_number, d.is_active, b.is_enabled
            FROM drivers d JOIN buses b ON b.bus_number = d.bus_number WHERE d.id = ? LIMIT 1`, [auth.userId]);
        if (!rows.length || !rows[0].is_active || !rows[0].is_enabled) {
            sessions.delete(auth.token);
            return res.status(401).json({ error: 'Driver access has been disabled' });
        }
        const driver = rows[0];
        return res.json({ user: { id: driver.id, name: driver.name || 'Driver', phone: driver.phone, busNumber: driver.bus_number, role: 'driver' } });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/me', async (req, res) => {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
        const rows = await q('SELECT id, name, email, role, hostel_id FROM users WHERE id = ? LIMIT 1', [auth.userId]);
        if (rows.length === 0) return res.status(404).json({ error: 'User not found' });
        return res.json({ status: 'success', user: publicUser(rows[0]) });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/buses', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = req.query.hostel || null;
        if (auth.role === 'student' && auth.hostelId && hostel && hostel !== auth.hostelId) {
            return res.status(403).json({ error: 'Students can only view their own hostel buses' });
        }

        const targetHostel = auth.role === 'student' ? auth.hostelId : hostel;
        const where = targetHostel ? 'WHERE b.assigned_hostel = ?' : '';
        const rows = await q(`${BUS_SELECT} ${where} ORDER BY b.bus_number`, targetHostel ? [targetHostel] : []);
        return res.json(rows.map(mapBus));
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/all-buses', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = auth.role === 'student' ? auth.hostelId : (req.query.hostel || null);
        const where = hostel ? 'WHERE b.assigned_hostel = ?' : '';
        const rows = await q(`${BUS_SELECT} ${where} ORDER BY b.bus_number`, hostel ? [hostel] : []);
        return res.json({ status: 'success', data: rows.map(mapBus) });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/buses/:busNumber', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const bus = await fetchBusByNumber(req.params.busNumber);
        if (!bus) return res.status(404).json({ error: 'Bus not found' });
        if (auth.role === 'student' && auth.hostelId !== bus.assignedHostel) {
            return res.status(403).json({ error: 'Access denied' });
        }
        return res.json(bus);
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/buses', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;

    try {
        const { busNumber, assignedHostel, driverName, driverPhone, latitude, longitude, route } = req.body || {};
        if (busNumber === undefined || !String(driverName || '').trim() || !String(driverPhone || '').trim()) {
            return res.status(400).json({ error: 'busNumber, driverName, and driverPhone are required' });
        }
        const normalizedPhone = String(driverPhone).replace(/\D/g, '').slice(-10);
        if (!/^[6-9]\d{9}$/.test(normalizedPhone)) return res.status(400).json({ error: 'Enter a valid 10-digit Indian mobile number' });
        const duplicatePhone = await q("SELECT bus_number FROM drivers WHERE regexp_replace(phone, '[^0-9]', '', 'g') LIKE ? LIMIT 1", [`%${normalizedPhone}`]);
        if (duplicatePhone.length) return res.status(409).json({ error: 'This mobile number is already assigned to another bus' });

        const existing = await q('SELECT bus_number FROM buses WHERE bus_number = ? LIMIT 1', [busNumber]);
        if (existing.length) {
            return res.status(409).json({ error: 'Bus number already exists' });
        }

        const targetHostel = auth.role === 'caretaker' ? auth.hostelId : (assignedHostel || auth.hostelId || 'BH1');
        if (!targetHostel) {
            return res.status(400).json({ error: 'assignedHostel is required' });
        }

        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            await client.query(
            'INSERT INTO buses (bus_number, assigned_hostel, status, latitude, longitude, speed, is_enabled, route) VALUES ($1, $2, $3, $4, $5, $6, true, $7)',
            [
                Number(busNumber),
                targetHostel,
                'idle',
                latitude !== undefined ? Number(latitude) : 23.7271,
                longitude !== undefined ? Number(longitude) : 92.7176,
                0,
                route || 'Hostel ↔ MBSE',
            ]
        );

            await client.query('INSERT INTO drivers (id,bus_number,name,phone,is_active) VALUES ($1,$2,$3,$4,true)', [
                uid('drv_'), Number(busNumber), String(driverName).trim(), normalizedPhone,
            ]);
            await client.query('COMMIT');
        } catch (error) {
            await client.query('ROLLBACK');
            if (error.code === '23505') return res.status(409).json({ error: 'Bus number already exists' });
            throw error;
        } finally {
            client.release();
        }

        const created = await fetchBusByNumber(busNumber);
        return res.status(201).json({ status: 'success', data: created });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.patch('/api/buses/:busNumber/driver', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;

    try {
        const busNumber = Number(req.params.busNumber);
        const access = await assertCaretakerAccess(busNumber, auth);
        if (!access.ok) {
            return res.status(access.code).json({ error: access.message });
        }

        const { driverName, driverPhone, pin } = req.body || {};
        if (!String(driverName || '').trim() || !String(driverPhone || '').trim()) {
            return res.status(400).json({ error: 'driverName and driverPhone are required' });
        }

        const normalizedPhone = String(driverPhone).replace(/\D/g, '').slice(-10);
        if (!/^[6-9]\d{9}$/.test(normalizedPhone)) return res.status(400).json({ error: 'Enter a valid 10-digit Indian mobile number' });
        if (pin !== undefined && pin !== '' && !/^\d{6}$/.test(String(pin))) return res.status(400).json({ error: 'PIN must contain exactly 6 digits' });
        const duplicate = await q("SELECT bus_number FROM drivers WHERE regexp_replace(phone, '[^0-9]', '', 'g') LIKE ? AND bus_number <> ? LIMIT 1", [`%${normalizedPhone}`, busNumber]);
        if (duplicate.length) return res.status(409).json({ error: 'This mobile number is already assigned to another bus' });

        const currentDriver = await q('SELECT id FROM drivers WHERE bus_number=? LIMIT 1', [busNumber]);
        const pinHash = pin ? await bcrypt.hash(String(pin), 10) : null;
        if (currentDriver.length) {
            if (pinHash) {
                await q('UPDATE drivers SET name=?, phone=?, pin_hash=?, is_active=true WHERE bus_number=?', [String(driverName).trim(), normalizedPhone, pinHash, busNumber]);
            } else {
                await q('UPDATE drivers SET name=?, phone=?, is_active=true WHERE bus_number=?', [String(driverName).trim(), normalizedPhone, busNumber]);
            }
        } else {
            await q('INSERT INTO drivers (id,bus_number,name,phone,pin_hash,is_active) VALUES (?,?,?,?,?,true)', [
                uid('drv_'), busNumber, String(driverName).trim(), normalizedPhone, pinHash,
            ]);
        }

        const updatedBus = await fetchBusByNumber(busNumber);
        return res.json({ status: 'success', data: updatedBus });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/schedules', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = auth.role === 'student' ? auth.hostelId : (req.query.hostel || null);
        const date = req.query.date || null;

        const rows = await q(
            `
            SELECT
                s.id AS _id,
                s.bus_number AS busNumber,
                to_char(s.date, 'YYYY-MM-DD') AS date,
                s.from_hostel_time AS fromHostelTime,
                s.from_mbse_time AS fromMBSETime,
                COALESCE(s.special_note, '') AS specialNote,
                COALESCE(s.updated_by, '') AS updatedBy
            FROM schedules s
            JOIN buses b ON b.bus_number = s.bus_number
            WHERE ($1::varchar IS NULL OR b.assigned_hostel = $1::varchar)
                AND ($2::date IS NULL OR s.date = $2::date)
            ORDER BY s.bus_number
      `,
                        [hostel, date]
        );

        return res.json(rows);
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/schedules', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;

    try {
        const { busNumber } = req.body || {};
        if (busNumber === undefined) {
            return res.status(400).json({ error: 'busNumber is required' });
        }

        const access = await assertCaretakerAccess(busNumber, auth);
        if (!access.ok) {
            return res.status(access.code).json({ error: access.message });
        }

        const scheduleDate = req.body.date || today();
        const fromHostelTime = req.body.fromHostelTime || '';
        const fromMBSETime = req.body.fromMBSETime || '';
        const specialNote = req.body.specialNote || '';

                await q(
                        `
            INSERT INTO schedules (id, bus_number, date, from_hostel_time, from_mbse_time, special_note, updated_by)
            VALUES ($1, $2, $3, $4, $5, $6, $7)
            ON CONFLICT (bus_number, date) DO UPDATE SET
                from_hostel_time = EXCLUDED.from_hostel_time,
                from_mbse_time = EXCLUDED.from_mbse_time,
                special_note = EXCLUDED.special_note,
                updated_by = EXCLUDED.updated_by,
                updated_at = CURRENT_TIMESTAMP
            `,
                        [
                                uid('sch_'),
                                busNumber,
                                scheduleDate,
                                fromHostelTime,
                                fromMBSETime,
                                specialNote,
                                auth.email,
                        ]
                );

        if (req.body.status) {
            const status = String(req.body.status).toLowerCase();
            await q('UPDATE buses SET status = ?, speed = ? WHERE bus_number = ?', [
                status,
                status === 'running' ? 25 : 0,
                busNumber,
            ]);
        }

                const rows = await q(
                        `
            SELECT
                s.id AS _id,
                s.bus_number AS busNumber,
                to_char(s.date, 'YYYY-MM-DD') AS date,
                s.from_hostel_time AS fromHostelTime,
                s.from_mbse_time AS fromMBSETime,
                COALESCE(s.special_note, '') AS specialNote,
                COALESCE(s.updated_by, '') AS updatedBy
            FROM schedules s
            WHERE s.bus_number = ? AND s.date = ?
            LIMIT 1
            `,
                        [busNumber, scheduleDate]
                );

        const bus = await fetchBusByNumber(busNumber);
        return res.json({ status: 'success', data: rows[0], bus });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.patch('/api/buses/:busNumber', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;

    try {
        const busNumber = Number(req.params.busNumber);
        const access = await assertCaretakerAccess(busNumber, auth);
        if (!access.ok) {
            return res.status(access.code).json({ error: access.message });
        }

        const updates = [];
        const params = [];

        if (req.body.status !== undefined) {
            const status = String(req.body.status).toLowerCase();
            updates.push('status = ?', 'speed = ?');
            params.push(status, status === 'running' ? 25 : 0);
        }
        if (req.body.latitude !== undefined) {
            updates.push('latitude = ?');
            params.push(Number(req.body.latitude));
        }
        if (req.body.longitude !== undefined) {
            updates.push('longitude = ?');
            params.push(Number(req.body.longitude));
        }
        if (req.body.isEnabled !== undefined) {
            updates.push('is_enabled = ?');
            params.push(req.body.isEnabled ? 1 : 0);
        }

        if (updates.length > 0) {
            params.push(busNumber);
            await q(`UPDATE buses SET ${updates.join(', ')} WHERE bus_number = ?`, params);
        }

        const bus = await fetchBusByNumber(busNumber);
        return res.json({ status: 'success', data: bus });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/notifications', async (req, res) => {
    const auth = requireAuth(req, res, ['student', 'caretaker', 'admin']);
    if (!auth) return;

    try {
        const hostel = auth.role === 'student' ? auth.hostelId : (req.query.hostel || null);
        const rows = await q(
            `
            SELECT
                id AS _id,
                title,
                message,
                type,
                bus_number AS busNumber,
                target_hostel AS targetHostel,
                to_char(sent_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS sentAt,
                is_read AS isRead
            FROM notifications
            WHERE ($1 IS NULL OR target_hostel = $1 OR target_hostel IS NULL)
            ORDER BY sent_at DESC
      `,
                        [hostel]
        );
        return res.json(rows.map((n) => ({ ...n, isRead: !!n.isRead })));
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/notifications/send', async (req, res) => {
    const auth = requireAuth(req, res, ['caretaker', 'admin']);
    if (!auth) return;

    try {
        const {
            title,
            message,
            type = 'general',
            busNumber = null,
            targetHostel = auth.hostelId || null,
        } = req.body || {};

        if (!title || !message) {
            return res.status(400).json({ error: 'title and message are required' });
        }

        const id = uid('n_');
        await q(
            'INSERT INTO notifications (id, title, message, type, bus_number, target_hostel, is_read, sent_by) VALUES (?, ?, ?, ?, ?, ?, 0, ?)',
            [id, title, message, type, busNumber, targetHostel, auth.email]
        );

                const rows = await q(
                        `
            SELECT
                id AS _id,
                title,
                message,
                type,
                bus_number AS busNumber,
                target_hostel AS targetHostel,
                to_char(sent_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS sentAt,
                is_read AS isRead
            FROM notifications
            WHERE id = $1
            LIMIT 1
            `,
                        [id]
                );

        const created = rows[0];
        return res.json({ ...created, isRead: !!created.isRead });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/api/location', async (req, res) => {
    const auth = requireAuth(req, res, ['driver']);
    if (!auth) return;
    const busNumber = Number(req.body?.busNumber);
    if (!Number.isInteger(busNumber) || busNumber !== Number(auth.busNumber)) {
        return res.status(403).json({ error: 'This token can update only its assigned bus' });
    }
    const lat = Number(req.body?.lat);
    const lng = Number(req.body?.lng);
    const clientSpeed = Number(req.body?.speed);
    const accuracy = Number(req.body?.accuracy);
    const timestamp = req.body?.timestamp ? new Date(req.body.timestamp) : new Date();
    const requestedStatus = req.body?.status === 'idle' ? 'idle' : null;
    if (!Number.isFinite(lat) || Math.abs(lat) > 90 || !Number.isFinite(lng) || Math.abs(lng) > 180 ||
        !Number.isFinite(clientSpeed) || clientSpeed < 0 || clientSpeed > 250 ||
        !Number.isFinite(accuracy) || accuracy < 0 || accuracy > 50 || Number.isNaN(timestamp.getTime()) ||
        timestamp.getTime() > Date.now() + 5 * 60 * 1000) {
        return res.status(400).json({ error: 'Invalid GPS fix; location accuracy must be 50m or better' });
    }

    let previous = driverLastFixes.get(busNumber);
    if (!previous) {
        const previousRows = await q('SELECT lat, lng, speed, ts FROM telemetry WHERE device_id=? ORDER BY received_at DESC, id DESC LIMIT 1', [`driver:${auth.userId}`]);
        if (previousRows.length) {
            const storedAt = Date.parse(previousRows[0].ts || '');
            if (Number.isFinite(storedAt)) {
                previous = { lat: Number(previousRows[0].lat), lng: Number(previousRows[0].lng), speed: Number(previousRows[0].speed || 0), timestamp: storedAt };
                driverLastFixes.set(busNumber, previous);
            }
        }
    }
    if (previous && timestamp.getTime() <= previous.timestamp) return res.json({ ok: true, stale: true });
    const point = { lat, lng, timestamp: timestamp.getTime() };
    let speed = clientSpeed;
    let heading = Number(req.body?.heading);
    if (previous) {
        const seconds = (point.timestamp - previous.timestamp) / 1000;
        if (seconds > 0) {
            const computed = haversineKm(previous, point) / (seconds / 3600);
            if (Number.isFinite(computed) && computed <= 180 && (clientSpeed > Math.max(computed * 2, 2) || computed > Math.max(clientSpeed * 2, 2))) speed = computed;
            if (!Number.isFinite(heading) || heading < 0 || heading >= 360) heading = bearingDegrees(previous, point);
            speed = previous.speed * 0.7 + speed * 0.3;
        }
    }
    if (!Number.isFinite(heading) || heading < 0 || heading >= 360) heading = 0;
    if (requestedStatus === 'idle') speed = 0;
    const status = requestedStatus || (speed > 1.5 ? 'running' : 'idle');
    const buses = await q(`SELECT b.assigned_hostel FROM buses b JOIN drivers d ON d.bus_number=b.bus_number
        WHERE b.bus_number=? AND b.is_enabled=true AND d.id=? AND d.is_active=true`, [busNumber, auth.userId]);
    if (!buses.length) return res.status(403).json({ error: 'Driver assignment is no longer active' });

    try {
        const client = await pool.connect();
        try {
            await client.query('BEGIN');
            await client.query('INSERT INTO telemetry (device_id, bus_id, lat, lng, speed, accuracy, heading, has_fix, ts, status) VALUES ($1, $2, $3, $4, $5, $6, $7, true, $8, $9)',
                [`driver:${auth.userId}`, String(busNumber), lat, lng, speed, accuracy, heading, timestamp.toISOString(), status]);
            await client.query('UPDATE buses SET latitude=$1, longitude=$2, speed=$3, status=$4 WHERE bus_number=$5', [lat, lng, speed, status, busNumber]);
            await client.query('COMMIT');
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
        const accepted = { ...point, speed };
        driverLastFixes.set(busNumber, accepted);
        const update = {
            busId: String(busNumber), busNumber, bus_number: busNumber,
            assignedHostel: buses[0].assigned_hostel, assigned_hostel: buses[0].assigned_hostel,
            lat, lng, latitude: lat, longitude: lng, speed, heading,
            accuracy, status, hasFix: true, timestamp: timestamp.toISOString(),
            lastUpdated: timestamp.toISOString(),
        };
        telemetryEmitter.emit('live_update', update);
        return res.status(200).json({ ok: true });
    } catch (error) {
        console.error('Driver location update failed:', error.message);
        return res.status(500).json({ error: 'Could not store location update' });
    }
});

app.post('/api/update-location', async (req, res) => {
    const clientKey = req.header('x-api-key');
    if (clientKey !== API_SECRET_KEY) {
        return res.status(401).json({ error: 'Unauthorized' });
    }

    try {
        const telemetry = normalizeTelemetry(req.body || {});
        const { lat: latNum, lng: lngNum, speed: speedNum, accuracy: accuracyNum } = telemetry;
        if (!Number.isFinite(latNum) || !Number.isFinite(lngNum) || Math.abs(latNum) > 90 || Math.abs(lngNum) > 180 || !Number.isFinite(speedNum) || speedNum < 0 || !Number.isFinite(accuracyNum)) {
            return res.status(400).json({ error: 'A valid latitude, longitude, speed, and accuracy are required.' });
        }

        const normalizedStatus = telemetry.status === 'active' ? 'running' : telemetry.status;
        const busNumber = Number(String(telemetry.busId || '').replace(/[^0-9]/g, ''));
        if (!Number.isInteger(busNumber) || busNumber <= 0) return res.status(400).json({ error: 'A valid bus_id is required.' });
        const buses = await q('SELECT assigned_hostel FROM buses WHERE bus_number=? AND is_enabled=true', [busNumber]);
        if (!buses.length) return res.status(404).json({ error: 'Bus not registered or disabled' });

        await q(
            'INSERT INTO telemetry (device_id, bus_id, lat, lng, speed, accuracy, has_fix, satellites, hdop, net_type, ts, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [telemetry.deviceId, telemetry.busId, latNum, lngNum, speedNum, accuracyNum, telemetry.hasFix ?? true, telemetry.satellites, telemetry.hdop, telemetry.netType, telemetry.timestamp || new Date().toISOString(), normalizedStatus]
        );

        await q('UPDATE buses SET latitude = ?, longitude = ?, speed = ?, status = ? WHERE bus_number = ?', [latNum, lngNum, speedNum, normalizedStatus, busNumber]);
        telemetryEmitter.emit('live_update', {
            bus_number: busNumber,
            busNumber,
            assigned_hostel: buses[0].assigned_hostel,
            hostel: buses[0].assigned_hostel,
            lat: latNum,
            lng: lngNum,
            speed: speedNum,
            status: normalizedStatus,
            hasFix: telemetry.hasFix ?? true,
            satellites: telemetry.satellites,
            hdop: telemetry.hdop,
            netType: telemetry.netType,
            timestamp: telemetry.timestamp || new Date().toISOString(),
        });

        return res.status(200).json({ message: 'Data received successfully', status: 'success' });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.get('/api/location/latest', async (_req, res) => {
    try {
                const rows = await q(
                        `
            SELECT
                device_id,
                bus_id,
                lat,
                lng,
                speed,
                accuracy,
                ts,
                status,
                to_char(received_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS received_at
            FROM telemetry
            ORDER BY received_at DESC
            LIMIT 1
            `
                );

        if (!rows.length) {
            return res.json({
                status: 'success',
                data: {
                    deviceId: 'ESP32-Device-1',
                    busId: 'Bus 5',
                    lat: 23.7271,
                    lng: 92.7176,
                    speed: 0,
                    accuracy: 1.0,
                    timestamp: new Date().toISOString(),
                    status: 'idle',
                },
            });
        }

        const latest = rows[0];
        const busRaw = latest.bus_id || '5';
        const busDigits = String(busRaw).replace(/[^0-9]/g, '');
        const busId = busDigits ? `Bus ${busDigits}` : String(busRaw);

        return res.json({
            status: 'success',
            data: {
                deviceId: latest.device_id || 'ESP32-Device-1',
                busId,
                lat: Number(latest.lat),
                lng: Number(latest.lng),
                speed: Number(latest.speed || 0),
                accuracy: Number(latest.accuracy || 1.0),
                timestamp: latest.ts || latest.received_at,
                status: latest.status || 'idle',
            },
        });
    } catch (error) {
        return res.status(500).json({ error: error.message });
    }
});

app.post('/update-gps', async (req, res) => {
    try {
        const { lat, lng } = req.body || {};
        if (lat === undefined || lng === undefined) {
            return res.status(400).json({ status: 'Error', message: 'Invalid Data' });
        }

        await q(
            'INSERT INTO telemetry (device_id, bus_id, lat, lng, speed, accuracy, ts, status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            ['ESP32-legacy', null, Number(lat), Number(lng), 0, 1.0, null, 'idle']
        );

        return res.status(200).json({ status: 'Success', message: 'Location Updated' });
    } catch (error) {
        return res.status(500).json({ status: 'Error', message: error.message });
    }
});

app.get('/get-location', async (_req, res) => {
    try {
                const rows = await q(
                        `
            SELECT lat, lng, to_char(received_at, 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS received_at
            FROM telemetry
            ORDER BY received_at DESC
            LIMIT 1
            `
                );

                const latest = rows[0] || { lat: 23.7271, lng: 92.7176, received_at: new Date().toISOString() };
        return res.json({ latitude: Number(latest.lat), longitude: Number(latest.lng), timestamp: latest.received_at });
    } catch (error) {
        return res.status(500).json({ status: 'Error', message: error.message });
    }
});

async function start() {
    try {
        await initializeDatabase();
        app.listen(port, '0.0.0.0', () => {
            console.log(`Server running on port ${port}`);
            console.log(`PostgreSQL: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}`);
            console.log('Seed logins:');
            console.log('  Student: student@nitmz.ac.in / student123');
            console.log('  Caretaker BH1: caretaker-bh1@nitmz.ac.in / caretaker123');
            console.log('  Caretaker GH1: caretaker-gh1@nitmz.ac.in / caretaker123');
            console.log(`ESP32 secure endpoint: http://<YOUR_PC_IP>:${port}/api/update-location`);
            console.log(`Flutter latest endpoint: http://<YOUR_PC_IP>:${port}/api/location/latest`);
        });
    } catch (error) {
        console.error('Failed to start server:', error.message);
        process.exit(1);
    }
}

start();
