import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const DB_FILE = process.env.DB_FILE || path.join(process.cwd(), 'hi_doc.db');
// Resolve schema file: when running inside backend folder process.cwd() is backend/, so schema at src/schema.sql
// Avoid duplicating 'backend' segment which caused path like backend/backend/src/schema.sql
const SCHEMA_PATH = path.join(process.cwd(), 'src', 'schema.sql');

export const db = new Database(DB_FILE);

export function migrate() {
  if (!fs.existsSync(SCHEMA_PATH)) {
    throw new Error(`Schema file not found at ${SCHEMA_PATH}`);
  }
  const sql = fs.readFileSync(SCHEMA_PATH, 'utf-8');
  
  db.exec('PRAGMA foreign_keys = ON;');
  console.log('Executing schema.sql...');
  db.exec(sql);
  console.log('Schema executed successfully');
  
  console.log('Running param targets upgrade...');
  upgradeParamTargetsIfNeeded();
  console.log('Param targets upgrade completed');
  
  console.log('Running messages table upgrade...');
  upgradeMessagesTableIfNeeded();
  console.log('Messages table upgrade completed');
  
  console.log('Running health_data table upgrade...');
  upgradeHealthDataTableIfNeeded();
  console.log('Health_data table upgrade completed');
  
  console.log('Running users table upgrade...');
  upgradeUsersTableIfNeeded();
  console.log('Users table upgrade completed');
  
  console.log('Seeding global param targets...');
  seedGlobalParamTargets();
  console.log('Global param targets seeded');
}

export function transaction<T>(fn: () => T): T {
  const trx = db.transaction(fn);
  return trx();
}

function seedGlobalParamTargets(): void {
  try {
    if (process.env.FORCE_RESEED_PARAM_TARGETS === '1') {
      try {
        db.prepare('DELETE FROM param_targets').run();
      } catch (err) {
        console.warn('Failed to clear param_targets:', err);
      }
    }
    
    const row = db.prepare('SELECT COUNT(*) as c FROM param_targets').get() as any;
    if (row && row.c > 0) {
      return;
    }

    // Resolve health_params.sql. Priority:
    // 1. Explicit env HEALTH_PARAMS_FILE
    // 2. backend/src/health_params.sql
    // 3. projectRoot/health_params.sql (one level up from backend when cwd is backend)
    const candidates: string[] = [];
    if (process.env.HEALTH_PARAMS_FILE) candidates.push(process.env.HEALTH_PARAMS_FILE);
    candidates.push(path.join(process.cwd(), 'src', 'health_params.sql'));
    candidates.push(path.join(process.cwd(), 'health_params.sql'));
    candidates.push(path.join(process.cwd(), '..', 'health_params.sql'));
    const sqlPath = candidates.find(p => {
      try { return fs.existsSync(p) && fs.statSync(p).isFile() && fs.readFileSync(p, 'utf-8').trim().length > 0; } catch { return false; }
    });
    if (!sqlPath) {
      console.warn('health_params.sql not found; skipping param_targets seed');
      return;
    }
    let sql = fs.readFileSync(sqlPath, 'utf-8');

    // Normalize line endings & ensure later duplicates overwrite earlier ones (some codes appear twice)
    // Convert plain INSERTs to INSERT OR REPLACE to avoid aborting on PK conflicts and let later range win.
    sql = sql.replace(/INSERT\s+INTO\s+param_targets/gi, 'INSERT OR REPLACE INTO param_targets');

    try {
      db.exec(sql);
      const countRow = db.prepare('SELECT COUNT(*) as c FROM param_targets').get() as any;
      console.log(`Seeded ${countRow.c} param_targets from ${path.relative(process.cwd(), sqlPath)}`);
    } catch (err) {
      console.warn('Failed to seed param_targets:', err);
    }
  } catch (e) {
    console.warn('param_targets seed failed (non-fatal)', e);
  }
}

function upgradeParamTargetsIfNeeded(): void {
  try {
    const info = db.prepare('PRAGMA table_info(param_targets)').all() as any[];
    if (info.length === 0) {
      return; // table absent
    }
    
    const hasUserId = info.some(c => c.name === 'user_id');
    const hasDescription = info.some(c => c.name === 'description');
    const hasNotes = info.some(c => c.name === 'notes');
    const hasOrganSystem = info.some(c => c.name === 'organ_system');

    // Desired final structure matches schema.sql: param_code, target_min, target_max, preferred_unit, description, notes, organ_system
    const isDesired = !hasUserId && hasDescription && hasNotes && hasOrganSystem && info.length === 7;
    if (isDesired) {
      return;
    }

    // Collapse to unique param_code and keep min/max across duplicates; keep first non-null description/notes/organ_system
    const selectDescription = hasDescription ? 'MAX(description) as description' : 'NULL as description';
    const selectNotes = hasNotes ? 'MAX(notes) as notes' : 'NULL as notes';
    const selectOrgan = hasOrganSystem ? 'MAX(organ_system) as organ_system' : 'NULL as organ_system';
    const base = `SELECT param_code, MIN(target_min) as target_min, MAX(target_max) as target_max, preferred_unit, ${selectDescription}, ${selectNotes}, ${selectOrgan} FROM param_targets GROUP BY param_code`;
    
    const rows = db.prepare(base).all() as any[];

    const transaction = db.transaction(() => {
      db.prepare('ALTER TABLE param_targets RENAME TO param_targets_old').run();
      db.prepare('CREATE TABLE param_targets ( param_code TEXT PRIMARY KEY, target_min REAL, target_max REAL, preferred_unit TEXT, description TEXT, notes TEXT, organ_system TEXT )').run();
      
      const stmt = db.prepare('INSERT INTO param_targets (param_code, target_min, target_max, preferred_unit, description, notes, organ_system) VALUES (?,?,?,?,?,?,?)');
      
      for (const r of rows) {
        stmt.run(r.param_code, r.target_min, r.target_max, r.preferred_unit, r.description, r.notes, r.organ_system);
      }
      
      db.prepare('DROP TABLE param_targets_old').run();
    });
    
    transaction();
  } catch (e) {
    console.warn('param_targets upgrade skipped', e);
  }
}

function upgradeMessagesTableIfNeeded(): void {
  try {
    console.log('Checking if messages table needs upgrade...');
    // Check if messages table exists and has the role column
    const info = db.prepare('PRAGMA table_info(messages)').all() as any[];
    
    if (info.length === 0) {
      console.log('Messages table does not exist, will be created by schema');
      // Table doesn't exist, schema.sql will create it
      return;
    }
    
    console.log('Messages table exists with columns:', info.map(c => c.name));
    
    const hasRole = info.some(c => c.name === 'role');
    if (hasRole) {
      console.log('Messages table already has role column');
      // Table already has role column
      return;
    }

    // Table exists but doesn't have role column - drop and recreate
    console.log('Messages table exists but missing role column, dropping and recreating...');
    try {
      db.prepare('DROP TABLE IF EXISTS messages').run();
      console.log('Successfully dropped old messages table');
    } catch (dropErr) {
      console.warn('Failed to drop messages table:', dropErr);
    }
  } catch (e) {
    console.warn('messages table upgrade skipped', e);
  }
}

function upgradeHealthDataTableIfNeeded(): void {
  try {
    console.log('Checking if health_data table needs upgrades...');
    const info = db.prepare('PRAGMA table_info(health_data)').all() as any[];
    
    if (info.length === 0) {
      console.log('Health_data table does not exist, will be created by schema');
      return;
    }
    
    console.log('Health_data table exists with columns:', info.map(c => c.name));
    
    const hasCategory = info.some(c => c.name === 'category');
    const hasQuantity = info.some(c => c.name === 'quantity');
    
    let needsUpgrade = false;
    
    if (!hasCategory) {
      // Add category column with default value
      console.log('Adding category column to health_data table...');
      db.prepare('ALTER TABLE health_data ADD COLUMN category TEXT DEFAULT "HEALTH_PARAMS"').run();
      console.log('Successfully added category column to health_data table');
      needsUpgrade = true;
    } else {
      console.log('Health_data table already has category column');
    }
    
    if (!hasQuantity) {
      // Add quantity column
      console.log('Adding quantity column to health_data table...');
      db.prepare('ALTER TABLE health_data ADD COLUMN quantity TEXT').run();
      console.log('Successfully added quantity column to health_data table');
      needsUpgrade = true;
    } else {
      console.log('Health_data table already has quantity column');
    }
    
    if (!needsUpgrade) {
      console.log('Health_data table is up to date');
    }
  } catch (e) {
    console.warn('health_data table upgrade skipped', e);
  }
}

function upgradeUsersTableIfNeeded(): void {
  try {
    const info = db.prepare('PRAGMA table_info(users)').all() as any[];
    
    if (info.length === 0) {
      console.log('Users table does not exist, will be created by schema');
      return;
    }
    
    console.log('Users table exists with columns:', info.map(c => c.name));
    
    const hasPhone = info.some(c => c.name === 'phone');
    const hasIsExternal = info.some(c => c.name === 'is_external');
    
    let needsUpgrade = false;
    
    if (!hasPhone) {
      // Add phone column
      console.log('Adding phone column to users table...');
      db.prepare('ALTER TABLE users ADD COLUMN phone TEXT').run();
      console.log('Successfully added phone column to users table');
      needsUpgrade = true;
    } else {
      console.log('Users table already has phone column');
    }
    
    if (!hasIsExternal) {
      // Add is_external column with default value
      console.log('Adding is_external column to users table...');
      db.prepare('ALTER TABLE users ADD COLUMN is_external INTEGER DEFAULT 0').run();
      console.log('Successfully added is_external column to users table');
      needsUpgrade = true;
    } else {
      console.log('Users table already has is_external column');
    }
    
    if (!needsUpgrade) {
      console.log('Users table is up to date');
    }
  } catch (e) {
    console.warn('users table upgrade skipped', e);
  }
}
