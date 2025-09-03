import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';
import { logger } from './logger.js';

const DB_FILE = process.env.DB_FILE || path.join(process.cwd(), '..', '.db', 'hi_doc.db');
const SCHEMA_PATH = path.join(process.cwd(), 'src', 'schema.sql');

export const db = new Database(DB_FILE);

export function initDb() {
  if (!fs.existsSync(SCHEMA_PATH)) throw new Error(`Schema file not found at ${SCHEMA_PATH}`);
  const sql = fs.readFileSync(SCHEMA_PATH, 'utf-8');
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec(sql);
  logger.info('Schema loaded');
}

export function transaction<T>(fn: () => T): T { return db.transaction(fn)(); }

// No migration / legacy cleanup logic – schema.sql is authoritative.
