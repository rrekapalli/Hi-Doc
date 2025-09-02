// Primary load of backend/.env via dotenv/config. We'll optionally fallback.
import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import express, { Request, Response } from 'express';
import compression from 'compression';
import { fileURLToPath } from 'url';
import cors from 'cors';
import router from './routes.js';
import { migrate, db } from './db.js';
import { logger } from './logger.js';
import { randomUUID } from 'crypto';

// Check required environment variables
if (!process.env.OPENAI_API_KEY) {
  logger.warn('OpenAI API key not set - AI features will be disabled');
}

logger.info('Starting Hi-Doc backend service');

const app = express();
// Disable ETag to avoid 304 confusing the client on dynamic JSON lists
app.set('etag', false);
// Trust proxy for correct client IP if behind reverse proxy
app.set('trust proxy', 1);
// Enable gzip/deflate compression for payloads >1kb
app.use(compression({ threshold: 1024 }));
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Import middleware and routes
import { authMiddleware } from './middleware/auth.js';
import profilesRouter from './routes/profiles.js';

logger.info('Logger initialized', { level: logger.level });
migrate();
// Apply runtime PRAGMAs (safe performance tweaks)
try {
  db.exec(`PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA temp_store = MEMORY; PRAGMA mmap_size = 268435456;`);
  logger.info('SQLite performance PRAGMAs applied');
} catch (e) { logger.warn('Failed applying PRAGMAs', { error: String(e) }); }
logger.info('Database migrated');

// Request logging middleware (adds reqId for correlation)
app.use((req, res, next) => {
  const reqId = randomUUID();
  (req as any).reqId = reqId;
  const start = Date.now();
  logger.info(`REQ ${req.method} ${req.url}`, { reqId });
  if (logger.level === 'debug') {
    logger.debug('REQ headers/body', { reqId, headers: req.headers, body: req.body });
  }
  res.on('finish', () => {
    const ms = Date.now() - start;
    logger.info(`RES ${req.method} ${req.url} ${res.statusCode}`, { reqId, ms });
  });
  next();
});

app.get('/healthz', (_req: Request, res: Response) => res.json({ ok: true }));

// Simple in-memory metrics (reset on restart)
const metrics: Record<string, { count: number; totalMs: number; }> = {};

// Metrics & timing middleware (after request logging for efficiency)
app.use((req, res, next) => {
  const startHr = process.hrtime.bigint();
  res.on('finish', () => {
    const durMs = Number(process.hrtime.bigint() - startHr) / 1_000_000;
    const key = `${req.method} ${(req.path || '').split('/:')[0]}`;
    const m = metrics[key] || (metrics[key] = { count: 0, totalMs: 0 });
    m.count++; m.totalMs += durMs;
  });
  next();
});

app.get('/metrics', (_req, res) => {
  const snapshot = Object.entries(metrics).map(([k,v]) => ({ route: k, count: v.count, avgMs: +(v.totalMs / v.count).toFixed(2) }));
  res.json({ snapshot, now: Date.now() });
});

// Add middleware and routes
app.use(authMiddleware);
app.use(profilesRouter);
app.use(router);

const BASE_PORT = Number(process.env.PORT || 4000);
const MAX_INCREMENT = 10;

function startServer(port: number, remainingFallbacks: number) {
  const server = app.listen(port, () => {
    logger.info(`Hi-Doc backend listening on :${port}`);
    if (port !== BASE_PORT) {
      logger.warn(`Using fallback port; original ${BASE_PORT} was busy`, { base: BASE_PORT, actual: port });
    }
  });
  server.on('error', (err: any) => {
    if (err.code === 'EADDRINUSE' && remainingFallbacks > 0) {
      const next = port + 1;
      logger.warn('Port in use, retrying', { current: port, next });
      startServer(next, remainingFallbacks - 1);
    } else {
      logger.error('Failed to start server', { error: String(err) });
      process.exit(1);
    }
  });
}

startServer(BASE_PORT, MAX_INCREMENT);

import { aiProviderStatus } from './ai.js';
logger.info('AI Providers', aiProviderStatus());
