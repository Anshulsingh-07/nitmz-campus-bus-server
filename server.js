const express = require('express');
const crypto = require('crypto');
const EventEmitter = require('events');
const bcrypt = require('bcrypt');
const { Pool } = require('pg');
require('dotenv').config();

if (process.env.NODE_ENV === 'production' && (!process.env.API_SECRET_KEY || !process.env.JWT_SECRET)) {
    throw new Error('API_SECRET_KEY and JWT_SECRET must be configured in production');
}

const app = express();
const telemetryEmitter = new EventEmitter();
telemetryEmitter.setMaxListeners(0);
const port = Number(process.env.PORT || 8080);
const API_SECRET_KEY = process.env.API_SECRET_KEY || 'BUSTRACKESP1SECRETKEY';
const DRIVER_JWT_SECRET = process.env.JWT_SECRET || API_SECRET_KEY;

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
const activeDriverSessions = new Map();
const driverLoginFailures = new Map();

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

function requireAuth(req, res, allowedRoles = null) {
    const header = req.header('authorization') || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token || !sessions.has(token) || sessions.get(token).expiresAt < Date.now()) {
        if (token && sessions.has(token)) sessions.delete(token);
        res.status(401).json({ error: 'Unauthorized' });
        return null;
    }

    const session = sessions.get(token);
    if (session.role === 'driver') {
        const parts = token.split('.');
        if (parts.length !== 3) { res.status(401).json({ error: 'Unauthorized' }); return null; }
        const signingInput = `${parts[0]}.${parts[1]}`;
        const expected = crypto.createHmac('sha256', DRIVER_JWT_SECRET).update(signingInput).digest();
        let actual;
        try { actual = Buffer.from(parts[2], 'base64url'); } catch (_) { actual = Buffer.alloc(0); }
        let claims;
        try { claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8')); } catch (_) { claims = null; }
        if (actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected) || claims?.sub !== session.userId || claims?.role !== 'driver' || claims?.exp * 1000 < Date.now()) {
            sessions.delete(token); activeDriverSessions.delete(session.userId);
            res.status(401).json({ error: 'Unauthorized' }); return null;
        }
    }
    if (allowedRoles && !allowedRoles.includes(session.role)) {
        res.status(403).json({ error: 'Forbidden' });
        return null;
    }

    return { token, ...session };
}

function createToken(user) {
    const expiresAt = Date.now() + (user.role === 'driver' ? 12 : 24 * 30) * 60 * 60 * 1000;
    let token;
    if (user.role === 'driver') {
        const base64url = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
        const signingInput = `${base64url({ alg: 'HS256', typ: 'JWT' })}.${base64url({ sub: user.id, role: 'driver', name: user.name, phone: user.phone, busNumber: user.bus_number, exp: Math.floor(expiresAt / 1000) })}`;
        const signature = crypto.createHmac('sha256', DRIVER_JWT_SECRET).update(signingInput).digest('base64url');
        token = `${signingInput}.${signature}`;
    } else {
        token = crypto.randomBytes(24).toString('hex');
    }
    sessions.set(token, {
        userId: user.id,
        email: user.email,
        role: user.role,
        hostelId: user.hostel_id,
        phone: user.phone || null,
        busNumber: user.bus_number || null,
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
LEFT JOIN drivers d ON d.bus_number = b.bus_number
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
            max: 10,
            idleTimeoutMillis: 30000,
        }
        : {
            host: DB_HOST,
            port: DB_PORT,
            user: DB_USER,
            password: DB_PASSWORD,
            database: DB_NAME,
            max: 10,
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
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  FOREIGN KEY (bus_number) REFERENCES buses(bus_number) ON DELETE CASCADE
);
`);

    await q(`
CREATE TABLE IF NOT EXISTS driver_accounts (
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
`);
    await q("CREATE UNIQUE INDEX IF NOT EXISTS driver_accounts_approved_bus_unique ON driver_accounts (bus_number) WHERE status IN ('pending','approved')");

    await q(`
CREATE TABLE IF NOT EXISTS schedules (
  id VARCHAR(40) PRIMARY KEY,
  bus_number INT NOT NULL,
  date DATE NOT NULL,
  from_hostel_time VARCHAR(20) NOT NULL,
  from_mbse_time VARCHAR(20) NOT NULL,
  special_note VARCHAR(255) NULL,
  updated_by VARCHAR(120) NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (bus_number, date),
  FOREIGN KEY (bus_number) REFERENCES buses(bus_number) ON DELETE CASCADE
);
`);

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
  ts VARCHAR(64) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'idle',
  received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
`);
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS has_fix BOOLEAN DEFAULT false');
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS satellites INT DEFAULT 0');
    await q('ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS hdop NUMERIC(6,2) DEFAULT 99.9');
    await q("ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS net_type VARCHAR(20) DEFAULT 'unknown'");

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

app.get('/api/auth/driver/buses', async (_req, res) => {
    try {
        const rows = await q(`SELECT b.bus_number AS "busNumber", b.route FROM buses b
          LEFT JOIN drivers d ON d.bus_number=b.bus_number AND d.is_active=true
          LEFT JOIN driver_accounts a ON a.bus_number=b.bus_number AND a.status IN ('pending','approved')
          WHERE b.is_enabled=true AND d.id IS NULL AND a.id IS NULL ORDER BY b.bus_number`);
        return res.json(rows);
    } catch (error) { return res.status(500).json({ error: error.message }); }
});

app.post('/api/auth/driver/register', async (req, res) => {
    try {
        const { name, phone, pin, busNumber } = req.body || {};
        if (!String(name || '').trim() || !/^(?:\+?91)?[6-9]\d{9}$/.test(String(phone || '').replace(/[\s-]/g, '')) || !/^\d{6}$/.test(String(pin || '')) || !Number.isInteger(Number(busNumber)))
            return res.status(400).json({ error: 'Enter a name, valid 10-digit Indian mobile number, six-digit PIN, and bus number' });
        const normalizedPhone = String(phone).replace(/\D/g, '').slice(-10);
        const bus = await q('SELECT bus_number FROM buses WHERE bus_number=? AND is_enabled=true', [Number(busNumber)]);
        if (!bus.length) return res.status(404).json({ error: 'Bus not found' });
        const existing = await q('SELECT id FROM driver_accounts WHERE phone=?', [normalizedPhone]);
        if (existing.length) return res.status(409).json({ error: 'This mobile number is already registered' });
        const claimed = await q(`SELECT id FROM drivers WHERE bus_number=? AND is_active=true
          UNION ALL SELECT id FROM driver_accounts WHERE bus_number=? AND status IN ('pending','approved') LIMIT 1`, [Number(busNumber), Number(busNumber)]);
        if (claimed.length) return res.status(409).json({ error: 'This bus already has an active or pending driver assignment. Ask an admin to unassign it first.' });
        const id = uid('drv_');
        const hash = await bcrypt.hash(String(pin), 12);
        await q('INSERT INTO driver_accounts (id,name,phone,pin_hash,bus_number,status) VALUES (?,?,?,?,?,?)', [id, String(name).trim(), normalizedPhone, hash, Number(busNumber), 'pending']);
        return res.status(201).json({ status: 'pending', message: 'Awaiting caretaker approval' });
    } catch (error) { return res.status(500).json({ error: error.message }); }
});

app.post('/api/auth/driver/login', async (req, res) => {
    try {
        const phone = String(req.body?.phone || '').replace(/\D/g, '').slice(-10);
        const pin = String(req.body?.pin || '');
        if (!/^[6-9]\d{9}$/.test(phone) || !/^\d{6}$/.test(pin)) return res.status(400).json({ error: 'Enter your 10-digit mobile number and six-digit PIN' });
        const lock = driverLoginFailures.get(phone);
        if (lock?.until > Date.now()) return res.status(429).json({ error: 'Too many failed attempts. Try again in 15 minutes.' });
        const rows = await q('SELECT * FROM driver_accounts WHERE phone=? LIMIT 1', [phone]);
        if (!rows.length || !(await bcrypt.compare(pin, rows[0].pin_hash))) {
            const priorFailures = lock?.until && lock.until <= Date.now() ? 0 : (lock?.count || 0);
            const failures = priorFailures + 1;
            driverLoginFailures.set(phone, { count: failures, until: failures >= 5 ? Date.now() + 15 * 60 * 1000 : 0 });
            return res.status(401).json({ error: 'Wrong mobile number or PIN' });
        }
        const driver = rows[0];
        if (driver.status === 'pending') return res.status(403).json({ error: 'pending_approval', message: 'Your account is awaiting caretaker approval' });
        if (driver.status === 'rejected') return res.status(403).json({ error: 'rejected', message: 'Your registration was rejected. Contact the caretaker for details.' });
        if (driver.status !== 'approved') return res.status(403).json({ error: 'inactive_driver', message: 'This driver account is not active. Contact an administrator.' });
        const activeToken = activeDriverSessions.get(driver.id);
        if (activeToken && sessions.has(activeToken) && sessions.get(activeToken).expiresAt > Date.now()) return res.status(409).json({ error: 'This driver is already signed in on another device. Sign out there or contact an administrator.' });
        driverLoginFailures.delete(phone);
        const user = { id: driver.id, name: driver.name, phone, role: 'driver', bus_number: driver.bus_number };
        const token = createToken(user);
        activeDriverSessions.set(driver.id, token);
        return res.json({ token, user: { id: driver.id, name: driver.name, phone, role: 'driver', busNumber: driver.bus_number } });
    } catch (error) { return res.status(500).json({ error: error.message }); }
});

app.get('/api/admin/drivers/pending', async (req, res) => {
    const auth = requireAuth(req, res, ['admin', 'caretaker']); if (!auth) return;
    try { return res.json(await q(`SELECT id,name,phone,bus_number AS "busNumber",created_at AS "createdAt" FROM driver_accounts WHERE status='pending' ORDER BY created_at`)); }
    catch (error) { return res.status(500).json({ error: error.message }); }
});

app.get('/api/admin/drivers/approved', async (req, res) => {
    const auth = requireAuth(req, res, ['admin', 'caretaker']); if (!auth) return;
    try { return res.json(await q(`SELECT id,name,phone,bus_number AS "busNumber",approved_at AS "createdAt" FROM driver_accounts WHERE status='approved' ORDER BY name`)); }
    catch (error) { return res.status(500).json({ error: error.message }); }
});

app.post('/api/admin/drivers/:id/approve', async (req, res) => {
    const auth = requireAuth(req, res, ['admin', 'caretaker']); if (!auth) return;
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const found = await client.query('SELECT * FROM driver_accounts WHERE id=$1 FOR UPDATE', [req.params.id]);
        if (!found.rowCount) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Driver not found' }); }
        const driver = found.rows[0];
        const conflict = await client.query("SELECT id FROM driver_accounts WHERE bus_number=$1 AND status='approved' AND id<>$2 FOR UPDATE", [driver.bus_number, driver.id]);
        if (conflict.rowCount) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'That bus is already assigned to another approved driver' }); }
        const busExists = await client.query('SELECT bus_number FROM buses WHERE bus_number=$1 AND is_enabled=true', [driver.bus_number]);
        if (!busExists.rowCount) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Bus not found' }); }
        await client.query('DELETE FROM drivers WHERE bus_number=$1', [driver.bus_number]);
        await client.query('INSERT INTO drivers (id,bus_number,name,phone,is_active) VALUES ($1,$2,$3,$4,true) ON CONFLICT (bus_number) DO UPDATE SET id=EXCLUDED.id,name=EXCLUDED.name,phone=EXCLUDED.phone,is_active=true', [driver.id, driver.bus_number, driver.name, driver.phone]);
        await client.query("UPDATE driver_accounts SET status='approved', approved_at=COALESCE(approved_at,CURRENT_TIMESTAMP) WHERE id=$1", [driver.id]);
        await client.query('COMMIT');
        return res.json({ status: 'approved' });
    } catch (error) { await client.query('ROLLBACK'); return res.status(500).json({ error: error.message }); }
    finally { client.release(); }
});

app.post('/api/admin/drivers/:id/reject', async (req, res) => {
    const auth = requireAuth(req, res, ['admin', 'caretaker']); if (!auth) return;
    try {
        const rows = await q('UPDATE driver_accounts SET status=?, approved_at = NULL WHERE id=? RETURNING *', ['rejected', req.params.id]);
        if (!rows.length) return res.status(404).json({ error: 'Driver not found' });
        return res.json({ status: 'rejected' });
    } catch (error) { return res.status(500).json({ error: error.message }); }
});

app.patch('/api/admin/drivers/:id', async (req, res) => {
    const auth = requireAuth(req, res, ['admin', 'caretaker']); if (!auth) return;
    const { action, busNumber } = req.body || {};
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const found = await client.query('SELECT * FROM driver_accounts WHERE id=$1 FOR UPDATE', [req.params.id]);
        if (!found.rowCount) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Driver not found' }); }
        const driver = found.rows[0];
        if (action === 'reject') await client.query("UPDATE driver_accounts SET status='rejected' WHERE id=$1", [driver.id]);
        else if (action === 'remove') {
            await client.query('DELETE FROM drivers WHERE bus_number=$1 AND id=$2', [driver.bus_number, driver.id]);
            await client.query("UPDATE driver_accounts SET status='removed' WHERE id=$1", [driver.id]);
            for (const [token, session] of sessions) if (session.userId === driver.id) sessions.delete(token);
            activeDriverSessions.delete(driver.id);
        } else if (action === 'approve' || action === 'reassign') {
            const nextBus = Number(busNumber || driver.bus_number);
            const conflict = await client.query("SELECT id FROM driver_accounts WHERE bus_number=$1 AND status='approved' AND id<>$2 FOR UPDATE", [nextBus, driver.id]);
            if (conflict.rowCount) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'That bus is already assigned to another approved driver' }); }
            const busExists = await client.query('SELECT bus_number FROM buses WHERE bus_number=$1 AND is_enabled=true', [nextBus]);
            const oldClaim = await client.query('SELECT id FROM drivers WHERE bus_number=$1 AND is_active=true AND id<>$2', [nextBus, driver.id]);
            if (oldClaim.rowCount) { await client.query('ROLLBACK'); return res.status(409).json({ error: 'Remove the current bus assignment before assigning this bus to another driver' }); }
            if (!busExists.rowCount) { await client.query('ROLLBACK'); return res.status(404).json({ error: 'Bus not found' }); }
            await client.query('DELETE FROM drivers WHERE bus_number=$1', [driver.bus_number]);
            await client.query('INSERT INTO drivers (id,bus_number,name,phone,is_active) VALUES ($1,$2,$3,$4,true) ON CONFLICT (bus_number) DO UPDATE SET id=EXCLUDED.id,name=EXCLUDED.name,phone=EXCLUDED.phone,is_active=true', [driver.id,nextBus,driver.name,driver.phone]);
            await client.query("UPDATE driver_accounts SET bus_number=$1,status='approved',approved_at=COALESCE(approved_at,CURRENT_TIMESTAMP) WHERE id=$2", [nextBus,driver.id]);
            for (const [token, session] of sessions) if (session.userId === driver.id) sessions.delete(token);
            activeDriverSessions.delete(driver.id);
        } else { await client.query('ROLLBACK'); return res.status(400).json({ error: 'action must be approve, reject, reassign, or remove' }); }
        await client.query('COMMIT'); return res.json({ status: action });
    } catch (error) { await client.query('ROLLBACK'); return res.status(500).json({ error: error.message }); }
    finally { client.release(); }
});

app.post('/api/auth/logout', (req, res) => {
    const auth = requireAuth(req, res); if (!auth) return;
    sessions.delete(auth.token); if (auth.role === 'driver') activeDriverSessions.delete(auth.userId);
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
                   t.lat, t.lng, t.has_fix, t.satellites, t.hdop, t.net_type, t.status AS telemetry_status, t.received_at
            FROM buses b
            LEFT JOIN LATERAL (
                SELECT bus_id, lat, lng, has_fix, satellites, hdop, net_type, status, received_at
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
                speed: Number(row.speed || 0),
                route: row.route,
                hostel: row.assigned_hostel,
                assigned_hostel: row.assigned_hostel,
                hasFix: row.has_fix ?? (row.lat != null && row.lng != null),
                lastUpdated: row.received_at || null,
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

app.get('/api/me', async (req, res) => {
    const auth = requireAuth(req, res);
    if (!auth) return;

    try {
        if (auth.role === 'driver') {
            const drivers = await q("SELECT id,name,phone,bus_number AS \"busNumber\",'driver' AS role FROM driver_accounts WHERE id=? AND status='approved' LIMIT 1", [auth.userId]);
            if (!drivers.length) return res.status(404).json({ error: 'Driver account not found' });
            return res.json({ status: 'success', user: drivers[0] });
        }
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
        if (busNumber === undefined || !driverName || !driverPhone) {
            return res.status(400).json({ error: 'busNumber, driverName, and driverPhone are required' });
        }

        const existing = await q('SELECT bus_number FROM buses WHERE bus_number = ? LIMIT 1', [busNumber]);
        if (existing.length) {
            return res.status(409).json({ error: 'Bus number already exists' });
        }

        const targetHostel = auth.role === 'caretaker' ? auth.hostelId : (assignedHostel || auth.hostelId || 'BH1');
        if (!targetHostel) {
            return res.status(400).json({ error: 'assignedHostel is required' });
        }

        await q(
            'INSERT INTO buses (bus_number, assigned_hostel, status, latitude, longitude, speed, is_enabled, route) VALUES (?, ?, ?, ?, ?, ?, 1, ?)',
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

        await q('INSERT INTO drivers (id, bus_number, name, phone, is_active) VALUES (?, ?, ?, ?, 1)', [
            uid('drv_'),
            Number(busNumber),
            String(driverName),
            String(driverPhone),
        ]);

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

        const { name, phone, isActive } = req.body || {};
        if (!name && !phone && isActive === undefined) {
            return res.status(400).json({ error: 'At least one of name, phone, isActive is required' });
        }

        const rows = await q('SELECT id FROM drivers WHERE bus_number = ? LIMIT 1', [busNumber]);
        if (!rows.length) {
            if (!name || !phone) {
                return res.status(400).json({ error: 'name and phone are required to create a new driver' });
            }
            await q('INSERT INTO drivers (id, bus_number, name, phone, is_active) VALUES (?, ?, ?, ?, ?)', [
                uid('drv_'),
                busNumber,
                name,
                phone,
                isActive === undefined ? 1 : (isActive ? 1 : 0),
            ]);
        } else {
            const updates = [];
            const params = [];
            if (name) {
                updates.push('name = ?');
                params.push(name);
            }
            if (phone) {
                updates.push('phone = ?');
                params.push(phone);
            }
            if (isActive !== undefined) {
                updates.push('is_active = ?');
                params.push(isActive ? 1 : 0);
            }
            params.push(busNumber);
            await q(`UPDATE drivers SET ${updates.join(', ')} WHERE bus_number = ?`, params);
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
    const auth = requireAuth(req, res, ['driver']); if (!auth) return;
    try {
        const driverRows = await q("SELECT bus_number FROM driver_accounts WHERE id=? AND status='approved'", [auth.userId]);
        if (!driverRows.length) return res.status(403).json({ error: 'No active bus assignment' });
        const assignedBus = Number(driverRows[0].bus_number);
        if (Number(req.body?.busNumber) !== assignedBus) return res.status(403).json({ error: 'Drivers can only publish location for their assigned bus' });
        const { lat, lng, speed=0, heading=0, accuracy=0, status='idle', timestamp=null } = req.body || {};
        if (![lat,lng,speed,heading,accuracy].every(v => Number.isFinite(Number(v))) || Number(accuracy) > 50) return res.status(400).json({ error: 'A valid GPS fix with accuracy of 50m or better is required' });
        const safeStatus = Number(speed) < 1.5 ? 'idle' : (status === 'running' ? 'running' : 'idle');
        await q('INSERT INTO telemetry (device_id,bus_id,lat,lng,speed,accuracy,has_fix,satellites,hdop,net_type,ts,status) VALUES (NULL,?,?,?,?,?,true,0,?,\'phone\',?,?)', [String(assignedBus),Number(lat),Number(lng),Number(speed),Number(accuracy),Number(accuracy),timestamp || new Date().toISOString(),safeStatus]);
        await q('UPDATE buses SET latitude=?,longitude=?,speed=?,status=? WHERE bus_number=?', [Number(lat),Number(lng),Number(speed),safeStatus,assignedBus]);
        const buses = await q('SELECT assigned_hostel FROM buses WHERE bus_number=?', [assignedBus]);
        telemetryEmitter.emit('live_update', { bus_number: assignedBus, busNumber: assignedBus, assigned_hostel: buses[0]?.assigned_hostel, hostel: buses[0]?.assigned_hostel, lat: Number(lat), lng: Number(lng), speed: Number(speed), status: safeStatus, hasFix: true, hdop: Number(accuracy), netType: 'phone', timestamp: timestamp || new Date().toISOString() });
        return res.json({ status: 'success' });
    } catch (error) { return res.status(500).json({ error: error.message }); }
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
        if (!Number.isNaN(busNumber) && busNumber > 0) {
            const phoneDriver = await q("SELECT id FROM driver_accounts WHERE bus_number=? AND status='approved' LIMIT 1", [busNumber]);
            if (phoneDriver.length) return res.status(403).json({ error: 'This bus location is published by its assigned driver phone' });
        }

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
