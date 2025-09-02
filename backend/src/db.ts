import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { logger } from './logger.js';

const DB_FILE = process.env.DB_FILE || path.join(process.cwd(), '..', '.db', 'hi_doc.db');
const SCHEMA_PATH = path.join(process.cwd(), 'src', 'schema.sql');

export const db = new Database(DB_FILE);

export function migrate() {
  if (!fs.existsSync(SCHEMA_PATH)) throw new Error(`Schema file not found at ${SCHEMA_PATH}`);
  let sql = fs.readFileSync(SCHEMA_PATH, 'utf-8');
  // IMPORTANT: Keep legacy prototype-user-12345 in raw schema to satisfy existing FK seeds.
  // Runtime middleware will migrate data to canonical 'prototype-user' after startup.
  // If someone edited schema to use 'prototype-user', map it back here to avoid FK failures during exec.
  sql = sql.replace(/prototype-user(?!-12345)/g, 'prototype-user-12345');
  db.exec('PRAGMA foreign_keys = ON;');
  // Legacy cleanup: aggressively drop any legacy tables referencing conversations/conversation_id
  try {
    const tables = db.prepare("SELECT name, sql FROM sqlite_master WHERE type='table'").all() as any[];
    const hasMessages = tables.some(t => t.name === 'messages');
    const hasConversations = tables.some(t => t.name === 'conversations');
    if (hasMessages) {
      const cols = db.prepare('PRAGMA table_info(messages)').all() as any[];
      const hasConversationIdCol = cols.some(c => c.name === 'conversation_id');
      if (hasConversationIdCol) {
  logger.warn('Dropping legacy messages table with conversation_id column');
        db.prepare('DROP TABLE IF EXISTS messages').run();
      } else if (!cols.some(c => c.name === 'profile_id')) {
  logger.warn('Messages table missing expected profile_id column; dropping to recreate');
        db.prepare('DROP TABLE IF EXISTS messages').run();
      }
    }
    if (hasConversations) {
  logger.warn('Dropping legacy conversations table');
      db.prepare('DROP TABLE IF EXISTS conversations').run();
    }
    // Drop any other tables that still include conversation_id in their SQL definition
    for (const t of tables) {
      if (!t.sql) continue;
      if (/conversation_id/.test(t.sql) || /conversations\b/.test(t.sql)) {
        if (!['messages','conversations'].includes(t.name)) {
          logger.warn(`Dropping legacy table ${t.name} referencing conversations`);
          db.prepare(`DROP TABLE IF EXISTS ${t.name}`).run();
        }
      }
    }
  } catch (e) {
    logger.warn('Legacy cleanup skipped', { error: String(e) });
  }
  logger.debug('Executing schema.sql (simplified migrate)...');
  db.exec(sql);
  logger.debug('Schema executed. Seeding param targets...');
  // Post-schema composite indexes (added after initial deployment for query optimization)
  try {
    db.exec(`
      CREATE INDEX IF NOT EXISTS idx_health_data_user_type_ts ON health_data(user_id, type, timestamp);
      CREATE INDEX IF NOT EXISTS idx_activities_user_ts ON activities(user_id, timestamp);
      CREATE INDEX IF NOT EXISTS idx_messages_sender_profile_time ON messages(sender_id, profile_id, created_at);
    `);
    logger.debug('Additional composite indexes ensured');
  } catch (e) {
    logger.warn('Failed creating composite indexes (non-fatal)', { error: String(e) });
  }
  seedGlobalParamTargets();
}

export function transaction<T>(fn: () => T): T { return db.transaction(fn)(); }

function seedGlobalParamTargets(): void {
  try {
    if (process.env.FORCE_RESEED_PARAM_TARGETS === '1') {
  try { db.prepare('DELETE FROM param_targets').run(); } catch (e) { logger.warn('Param targets clear failed', { error: String(e) }); }
    }
    const c = db.prepare('SELECT COUNT(*) as c FROM param_targets').get() as any;
    if (c && c.c > 0) return;
    const candidates = [
      process.env.HEALTH_PARAMS_FILE,
      path.join(process.cwd(), 'src', 'health_params.sql'),
      path.join(process.cwd(), 'health_params.sql'),
      path.join(process.cwd(), '..', 'health_params.sql')
    ].filter(Boolean) as string[];
    const sqlPath = candidates.find(p => { try { return fs.existsSync(p) && fs.statSync(p).isFile() && fs.readFileSync(p,'utf-8').trim().length>0; } catch { return false; } });
  if (!sqlPath) { logger.warn('health_params.sql not found; skipping param_targets seed'); return; }
    let sql = fs.readFileSync(sqlPath,'utf-8');
    sql = sql.replace(/INSERT\s+INTO\s+param_targets/gi,'INSERT OR REPLACE INTO param_targets');
    db.exec(sql);
    const after = db.prepare('SELECT COUNT(*) as c FROM param_targets').get() as any;
  logger.info(`Seeded ${after.c} param_targets from ${path.relative(process.cwd(), sqlPath)}`);
  } catch (e) {
  logger.warn('param_targets seed failed (non-fatal)', { error: String(e) });
  }
}

// All legacy/upgrade logic removed – rely on clean schema apply.
