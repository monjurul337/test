/**
 * IVAC Visa Bot - Backend Server
 * Manages session pairing between Android app (OTP source) and Chrome Extension (OTP consumer).
 * Provides WebSocket and REST endpoints.
 */

import express from 'express';
import { WebSocketServer } from 'ws';
import { createServer } from 'http';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { v4 as uuidv4 } from 'uuid';
import dotenv from 'dotenv';
import winston from 'winston';

dotenv.config();

// ─── Logger ────────────────────────────────────────────────────────────────────
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.colorize(),
    winston.format.printf(({ timestamp, level, message }) => `[${timestamp}] ${level}: ${message}`)
  ),
  transports: [new winston.transports.Console()],
});

// ─── State ─────────────────────────────────────────────────────────────────────
/**
 * sessions: Map<sessionId, SessionData>
 * SessionData {
 *   sessionId: string,
 *   pairingCode: string,           // 6-digit code shown in Chrome Extension popup
 *   extensionSocket: WebSocket|null,
 *   androidSocket: WebSocket|null,
 *   otpBuffer: OTPEntry[],         // Pending OTPs not yet consumed
 *   createdAt: number,
 *   lastActivity: number,
 * }
 */
const sessions = new Map();
const pairingCodeIndex = new Map();

// ─── Helpers ───────────────────────────────────────────────────────────────────
function generatePairingCode() {
  let code;
  do {
    code = Math.floor(100000 + Math.random() * 900000).toString();
  } while (pairingCodeIndex.has(code));
  return code;
}

function createSession() {
  const sessionId = uuidv4();
  const pairingCode = generatePairingCode();
  const session = {
    sessionId,
    pairingCode,
    extensionSocket: null,
    androidSocket: null,
    otpBuffer: [],
    createdAt: Date.now(),
    lastActivity: Date.now(),
  };
  sessions.set(sessionId, session);
  pairingCodeIndex.set(pairingCode, sessionId);
  logger.info(`Session created: ${sessionId} (code: ${pairingCode})`);
  return session;
}

function touchSession(session) {
  session.lastActivity = Date.now();
}

function sendJSON(ws, data) {
  if (ws && ws.readyState === 1) {
    try { ws.send(JSON.stringify(data)); }
    catch (err) { logger.error(`Send error: ${err.message}`); }
  }
}

function broadcastSessionStatus(session) {
  const status = {
    type: 'session_status',
    sessionId: session.sessionId,
    androidConnected: !!session.androidSocket,
    extensionConnected: !!session.extensionSocket,
    pendingOtps: session.otpBuffer.length,
    timestamp: Date.now(),
  };
  sendJSON(session.extensionSocket, status);
  sendJSON(session.androidSocket, status);
}

// ─── Session Cleanup every 10 minutes, expire after 2h idle ───────────────────
setInterval(() => {
  const now = Date.now();
  for (const [id, session] of sessions) {
    if (now - session.lastActivity > 2 * 60 * 60 * 1000) {
      logger.info(`Expiring idle session ${id}`);
      if (session.extensionSocket) session.extensionSocket.close();
      if (session.androidSocket) session.androidSocket.close();
      pairingCodeIndex.delete(session.pairingCode);
      sessions.delete(id);
    }
  }
}, 10 * 60 * 1000);

// ─── Express App ───────────────────────────────────────────────────────────────
const app = express();
app.use(helmet({ contentSecurityPolicy: false }));
app.use(cors({ origin: '*', methods: ['GET', 'POST', 'DELETE'] }));
app.use(express.json({ limit: '10kb' }));
const limiter = rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true });
app.use(limiter);

// POST /api/sessions - Chrome Extension calls this on startup
app.post('/api/sessions', (req, res) => {
  const session = createSession();
  res.json({
    success: true,
    sessionId: session.sessionId,
    pairingCode: session.pairingCode,
    wsUrl: `ws://${req.headers.host}/ws`,
  });
});

// GET /api/sessions/:sessionId - Get session status
app.get('/api/sessions/:sessionId', (req, res) => {
  const session = sessions.get(req.params.sessionId);
  if (!session) return res.status(404).json({ success: false, error: 'Session not found' });
  res.json({
    success: true,
    sessionId: session.sessionId,
    pairingCode: session.pairingCode,
    androidConnected: !!session.androidSocket,
    extensionConnected: !!session.extensionSocket,
    pendingOtps: session.otpBuffer.length,
  });
});

// POST /api/otp - Android pushes OTP via HTTP fallback
app.post('/api/otp', (req, res) => {
  const { pairingCode, otp, rawMessage, sender } = req.body;
  if (!pairingCode || !otp) {
    return res.status(400).json({ success: false, error: 'pairingCode and otp are required' });
  }
  const sessionId = pairingCodeIndex.get(pairingCode);
  if (!sessionId) return res.status(404).json({ success: false, error: 'Invalid pairing code' });

  const session = sessions.get(sessionId);
  touchSession(session);
  const otpEntry = { otp, rawMessage: rawMessage || '', sender: sender || 'UNKNOWN', receivedAt: Date.now() };
  session.otpBuffer.push(otpEntry);

  if (session.extensionSocket) {
    sendJSON(session.extensionSocket, { type: 'otp', ...otpEntry });
    logger.info(`OTP forwarded to extension for session ${sessionId}: ${otp}`);
  } else {
    logger.info(`OTP buffered for session ${sessionId}: ${otp} (extension not connected)`);
  }
  res.json({ success: true, queued: !session.extensionSocket });
});

// GET /api/otp/:sessionId - Extension polls for pending OTPs
app.get('/api/otp/:sessionId', (req, res) => {
  const session = sessions.get(req.params.sessionId);
  if (!session) return res.status(404).json({ success: false, error: 'Session not found' });
  touchSession(session);
  const otps = session.otpBuffer.splice(0);
  res.json({ success: true, otps });
});

// DELETE /api/sessions/:sessionId - Delete session
app.delete('/api/sessions/:sessionId', (req, res) => {
  const session = sessions.get(req.params.sessionId);
  if (!session) return res.status(404).json({ success: false, error: 'Session not found' });
  if (session.extensionSocket) session.extensionSocket.close();
  if (session.androidSocket) session.androidSocket.close();
  pairingCodeIndex.delete(session.pairingCode);
  sessions.delete(req.params.sessionId);
  logger.info(`Session deleted: ${req.params.sessionId}`);
  res.json({ success: true });
});

// GET /health
app.get('/health', (req, res) => {
  res.json({ status: 'ok', sessions: sessions.size, uptime: process.uptime() });
});

// ─── HTTP + WebSocket Server ───────────────────────────────────────────────────
const server = createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  logger.info(`WebSocket connected from ${req.socket.remoteAddress}`);
  let assignedSession = null;
  let clientType = null;

  ws.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch { return ws.send(JSON.stringify({ type: 'error', error: 'Invalid JSON' })); }

    switch (msg.type) {
      case 'extension_connect': {
        const session = sessions.get(msg.sessionId);
        if (!session) return sendJSON(ws, { type: 'error', error: 'Session not found' });
        session.extensionSocket = ws;
        assignedSession = session;
        clientType = 'extension';
        touchSession(session);
        sendJSON(ws, { type: 'connected', role: 'extension', sessionId: session.sessionId, pairingCode: session.pairingCode });
        broadcastSessionStatus(session);
        if (session.otpBuffer.length > 0) {
          const pending = session.otpBuffer.splice(0);
          pending.forEach(entry => sendJSON(ws, { type: 'otp', ...entry }));
          logger.info(`Flushed ${pending.length} buffered OTP(s) to extension`);
        }
        break;
      }
      case 'android_connect': {
        const sessionId = pairingCodeIndex.get(msg.pairingCode);
        if (!sessionId) return sendJSON(ws, { type: 'error', error: 'Invalid pairing code' });
        const session = sessions.get(sessionId);
        session.androidSocket = ws;
        assignedSession = session;
        clientType = 'android';
        touchSession(session);
        sendJSON(ws, { type: 'connected', role: 'android', sessionId: session.sessionId });
        broadcastSessionStatus(session);
        logger.info(`Android paired with session ${session.sessionId} (code: ${msg.pairingCode})`);
        break;
      }
      case 'otp': {
        if (!assignedSession || clientType !== 'android') return sendJSON(ws, { type: 'error', error: 'Not authenticated as android' });
        const { otp, rawMessage, sender } = msg;
        if (!otp) return sendJSON(ws, { type: 'error', error: 'otp field required' });
        touchSession(assignedSession);
        const otpEntry = { otp, rawMessage: rawMessage || '', sender: sender || 'UNKNOWN', receivedAt: Date.now() };
        if (assignedSession.extensionSocket) {
          sendJSON(assignedSession.extensionSocket, { type: 'otp', ...otpEntry });
          logger.info(`OTP relayed via WS for session ${assignedSession.sessionId}: ${otp}`);
        } else {
          assignedSession.otpBuffer.push(otpEntry);
          logger.info(`OTP buffered for session ${assignedSession.sessionId}: ${otp}`);
        }
        sendJSON(ws, { type: 'otp_ack', otp, relayed: !!assignedSession.extensionSocket });
        break;
      }
      case 'ping':
        sendJSON(ws, { type: 'pong', timestamp: Date.now() });
        if (assignedSession) touchSession(assignedSession);
        break;
      default:
        sendJSON(ws, { type: 'error', error: `Unknown message type: ${msg.type}` });
    }
  });

  ws.on('close', () => {
    if (!assignedSession) return;
    if (clientType === 'extension') { assignedSession.extensionSocket = null; logger.info(`Extension disconnected from ${assignedSession.sessionId}`); }
    else if (clientType === 'android') { assignedSession.androidSocket = null; logger.info(`Android disconnected from ${assignedSession.sessionId}`); }
    broadcastSessionStatus(assignedSession);
  });

  ws.on('error', (err) => logger.error(`WebSocket error: ${err.message}`));
  sendJSON(ws, { type: 'welcome', message: 'IVAC Visa Bot Backend. Authenticate with extension_connect or android_connect.' });
});

// ─── Start ────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  logger.info(`IVAC Visa Bot Backend running on http://localhost:${PORT}`);
  logger.info(`WebSocket endpoint: ws://localhost:${PORT}/ws`);
});
