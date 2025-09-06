import { Router, Request as ExpressRequest, Response, NextFunction } from 'express';
import { db } from './db.js';
import { randomUUID } from 'crypto';
import { z } from 'zod';
import { signToken, verifyToken } from './jwtUtil.js';
import { interpretMessage, aiProviderStatus, AiInterpretation, getHealthDataEntryPrompt, getHealthDataTrendPrompt, clearPromptCache } from './ai.js';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

// Fix __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Extend Express Request to include user
interface Request extends ExpressRequest {
  user?: {
    id: string;
    name?: string;
    email?: string;
  };
}
import { logger } from './logger.js';
import { verifyMicrosoftIdToken } from './msAuth.js';

// Reports directory (project root ./reports). We only persist the filename in DB.
const reportsDir = path.join(__dirname, '../../reports');

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: function (_req, _file, cb) {
    if (!fs.existsSync(reportsDir)) {
      fs.mkdirSync(reportsDir, { recursive: true });
    }
    cb(null, reportsDir);
  },
  filename: function (_req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = path.extname(file.originalname);
    cb(null, 'report-' + uniqueSuffix + ext);
  }
});

const upload = multer({ 
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit
  },
  fileFilter: function (req, file, cb) {
    // Accept images, PDFs, and documents
    const allowedExtensions = /\.(jpeg|jpg|png|pdf|doc|docx|txt|md)$/i;
    const allowedMimeTypes = /^(image\/.*|application\/pdf|text\/.*|application\/msword|application\/vnd\.openxmlformats-officedocument\.wordprocessingml\.document|application\/octet-stream)$/;
    
    const extname = allowedExtensions.test(file.originalname);
    const mimetype = allowedMimeTypes.test(file.mimetype);
    
    if (mimetype && extname) {
      return cb(null, true);
    } else {
      cb(new Error(`File type not allowed: ${file.originalname} (${file.mimetype})`));
    }
  }
});
interface DbMessage {
  id: string;
  profile_id: string;
  sender_id: string;
  user_id: string;
  role: 'user' | 'system' | 'assistant';
  content: string;
  created_at: number;
  processed?: number;
  interpretation_json?: string;
}

const router = Router();

// Prototype mode: Skip authentication and use a hardcoded user ID
let prototypeUserMigrationDone = false;
router.use((req: Request, res: Response, next: NextFunction) => {
  // Canonical prototype user ID (aligned with Flutter client)
  const canonicalUserId = 'prototype-user';
  const legacyUserId = 'prototype-user-12345';
  const defaultEmail = 'prototype@example.com';

  try {
    // Ensure canonical user exists
    let user = db.prepare('SELECT * FROM users WHERE id = ?').get(canonicalUserId);
    if (!user) {
      db.prepare('INSERT OR IGNORE INTO users (id, name, email, photo_url) VALUES (?,?,?,?)')
        .run(canonicalUserId, 'Prototype User', defaultEmail, null);
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(canonicalUserId);
      logger.debug('Canonical prototype user ensured', { user });
    }

    // One-time migration from legacy user id
    if (!prototypeUserMigrationDone) {
      const legacyExists = db.prepare('SELECT 1 FROM users WHERE id = ?').get(legacyUserId);
      if (legacyExists) {
        logger.info('Running prototype user ID migration from legacy to canonical');
        const tx = db.transaction(() => {
          // Insert canonical user if not present (already ensured above)
          // Update referencing tables first by inserting canonical user (done) then updating foreign keys
          const tablesWithUserId = [
            'medications','messages','reports','health_data','reminders','activities','profile_members'
          ];
            for (const t of tablesWithUserId) {
              try {
                db.prepare(`UPDATE ${t} SET user_id = ? WHERE user_id = ?`).run(canonicalUserId, legacyUserId);
              } catch (e) {
                logger.warn('Migration: failed updating table', { table: t, error: e });
              }
            }
          // sender_id also references user (messages)
          try { db.prepare('UPDATE messages SET sender_id = ? WHERE sender_id = ?').run(canonicalUserId, legacyUserId); } catch {}
          // Finally remove legacy user row (only if no refs remain)
          try { db.prepare('DELETE FROM users WHERE id = ?').run(legacyUserId); } catch {}
        });
        tx();
        logger.info('Prototype user ID migration complete');
      }
      prototypeUserMigrationDone = true;
    }

    // Attach user to request
    (req as any).userId = canonicalUserId;
    (req as any).user = { id: canonicalUserId, name: 'Prototype User', email: defaultEmail };
  } catch (e) {
    logger.error('Error in prototype user middleware', { error: e });
  }
  next();
});

// Import conversation-related functions
import {
  getProfiles,
  getMessages,
  sendMessage,
  createProfile,
  markProfileAsRead,
  updateProfileTitle,
  addProfileMembers,
  removeProfileMember,
  getProfileMembers,
} from './profiles.js';

// Conversation routes
router.get('/api/profiles', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

  const profiles = await getProfiles(userId);
  res.json(profiles);
  } catch (error) {
  logger.error('Error getting profiles:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/api/profiles/:id/messages', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { before, limit } = req.query;
    const messages = await getMessages(
      id,
      userId,
      limit ? parseInt(limit as string) : undefined,
      before ? parseInt(before as string) : undefined
    );
    res.json(messages);
  } catch (error) {
    logger.error('Error getting messages:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/profiles/:id/messages', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { content, contentType = 'text' } = req.body;
    if (!content) {
      return res.status(400).json({ error: 'Content is required' });
    }

    const messageId = await sendMessage({
  profile_id: id,
      sender_id: userId,
      role: 'user',
      content,
      content_type: contentType,
      processed: 0,
    });

    res.json({ id: messageId });
  } catch (error) {
    logger.error('Error sending message:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/profiles', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { title, type, memberIds } = req.body;
    if (!type || !memberIds || !Array.isArray(memberIds)) {
      return res.status(400).json({ error: 'Invalid request body' });
    }

    // Always include the creator in the members list
    const uniqueMemberIds = Array.from(new Set([...memberIds, userId]));

  const profileId = await createProfile(
      title,
      type,
      uniqueMemberIds,
      userId
    );

  res.json({ id: profileId });
  } catch (error) {
    logger.error('Error creating conversation:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/profiles/:id/read', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

  await markProfileAsRead(id, userId);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error marking conversation as read:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/api/profiles/:id/title', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { title } = req.body;
    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

  await updateProfileTitle(id, title);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error updating conversation title:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/profiles/:id/members', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { userIds } = req.body;
    if (!userIds || !Array.isArray(userIds)) {
      return res.status(400).json({ error: 'User IDs array is required' });
    }

  await addProfileMembers(id, userIds);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error adding conversation members:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/api/profiles/:id/members/:userId', async (req: Request, res: Response) => {
  try {
    const { id, userId } = req.params;
  await removeProfileMember(id, userId);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error removing conversation member:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/api/profiles/:id/members', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
  const members = await getProfileMembers(id);
    res.json(members);
  } catch (error) {
    logger.error('Error getting conversation members:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Search users endpoint for creating new profiles (chat entities)
router.get('/api/users/search', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { query, limit = 20 } = req.query;
    const searchLimit = Math.min(parseInt(limit as string) || 20, 50);
    
    let users;
    if (query && typeof query === 'string') {
      // Search users by name or email (case-insensitive)
      const searchQuery = `%${query.toLowerCase()}%`;
      users = db.prepare(`
        SELECT id, name, email, photo_url 
        FROM users 
        WHERE id != ? AND (
          LOWER(name) LIKE ? OR 
          LOWER(email) LIKE ?
        )
        ORDER BY name ASC
        LIMIT ?
      `).all(userId, searchQuery, searchQuery, searchLimit);
    } else {
      // Return all users except current user
      users = db.prepare(`
        SELECT id, name, email, photo_url 
        FROM users 
        WHERE id != ?
        ORDER BY name ASC
        LIMIT ?
      `).all(userId, searchLimit);
    }

    res.json(users);
  } catch (error) {
    logger.error('Error searching users:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// -------------------------------
// Medications & Schedules API
// -------------------------------

// List medications for a profile
router.get('/api/medications', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const profileId = (req.query.profile_id as string) || (req.query.profileId as string);
    if (!userId || !profileId) return res.status(400).json({ error: 'profile_id required' });
    let rows = db.prepare(`SELECT * FROM medications WHERE user_id = ? AND profile_id = ? ORDER BY name ASC`).all(userId, profileId);
    if (rows.length == 0) {
      // Fallback: check legacy user id rows and migrate on the fly
      const legacyUserId = 'prototype-user-12345';
      const legacyRows = db.prepare(`SELECT * FROM medications WHERE user_id = ? AND profile_id = ? ORDER BY name ASC`).all(legacyUserId, profileId);
      if (legacyRows.length > 0) {
        logger.warn('Migrating legacy medication rows to canonical user id', { count: legacyRows.length, profileId });
        const tx = db.transaction(() => {
          db.prepare('UPDATE medications SET user_id = ? WHERE user_id = ?').run(userId, legacyUserId);
        });
        try { tx(); } catch (e) { logger.error('Legacy medication migration failed', { error: e }); }
        rows = db.prepare(`SELECT * FROM medications WHERE user_id = ? AND profile_id = ? ORDER BY name ASC`).all(userId, profileId);
      }
    }
    res.json(rows);
  } catch (e) {
    logger.error('Error listing medications', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create medication
router.post('/api/medications', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { profileId, name, notes, medicationUrl } = req.body;
    if (!userId || !profileId || !name) return res.status(400).json({ error: 'profileId and name required' });
    // Ensure normalized schema columns exist (executed once then cached)
    try {
      const globalAny: any = globalThis as any;
      if (!globalAny.__medicationsSchemaChecked) {
        const cols = db.prepare('PRAGMA table_info(medications)').all() as any[];
        const colNames = new Set(cols.map(c => c.name as string));
        const desired: Record<string,string> = {
          notes: 'TEXT',
          medication_url: 'TEXT',
          created_at: 'INTEGER',
          updated_at: 'INTEGER',
        };
        const missing = Object.keys(desired).filter(c => !colNames.has(c));
        if (missing.length > 0) {
          logger.warn('Medications table missing columns; applying in-place migration', { missing });
          const tx = db.transaction(() => {
            for (const m of missing) {
              const type = desired[m];
              try { db.prepare(`ALTER TABLE medications ADD COLUMN ${m} ${type}`).run(); }
              catch (e) { logger.error('Failed to add medications column', { column: m, error: e }); }
            }
            const now = Date.now();
            if (missing.includes('created_at')) { db.prepare('UPDATE medications SET created_at = ? WHERE created_at IS NULL').run(now); }
            if (missing.includes('updated_at')) { db.prepare('UPDATE medications SET updated_at = ? WHERE updated_at IS NULL').run(now); }
          });
          tx();
        }
        globalAny.__medicationsSchemaChecked = true;
      }
    } catch (e) { logger.error('Medication schema self-check failed (non-fatal)', { error: e }); }
    const id = randomUUID();
    const now = Date.now();
    db.prepare(`INSERT INTO medications (id,user_id,profile_id,name,notes,medication_url,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)`)
      .run(id, userId, profileId, name, notes || null, medicationUrl || null, now, now);
    res.json({ id });
  } catch (e) {
    const err: any = e;
    logger.error('Error creating medication', { message: err?.message, error: err, stack: err?.stack });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get medication detail with schedules + times
router.get('/api/medications/:id', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { id } = req.params;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });
    const med = db.prepare('SELECT * FROM medications WHERE id = ? AND user_id = ?').get(id, userId);
    if (!med) return res.status(404).json({ error: 'Not found' });
    const schedules = db.prepare('SELECT * FROM medication_schedules WHERE medication_id = ? ORDER BY start_date ASC').all(id);
    const schedulesWithTimes = schedules.map((s: any) => {
      const times = db.prepare('SELECT * FROM medication_schedule_times WHERE schedule_id = ? ORDER BY sort_order ASC, time_local ASC').all(s.id);
      return { ...s, times };
    });
    res.json({ ...med, schedules: schedulesWithTimes });
  } catch (e) {
    logger.error('Error getting medication detail', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update medication
router.put('/api/medications/:id', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { id } = req.params;
    const { name, notes, medicationUrl } = req.body;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });
    const now = Date.now();
    const stmt = db.prepare('UPDATE medications SET name = COALESCE(?, name), notes = COALESCE(?, notes), medication_url = COALESCE(?, medication_url), updated_at = ? WHERE id = ? AND user_id = ?');
    const info = stmt.run(name || null, notes || null, medicationUrl || null, now, id, userId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error updating medication', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete medication (cascade removes schedules/times via FK)
router.delete('/api/medications/:id', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    const { id } = req.params;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });
    const info = db.prepare('DELETE FROM medications WHERE id = ? AND user_id = ?').run(id, userId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error deleting medication', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create schedule for medication
router.post('/api/medications/:id/schedules', (req: Request, res: Response) => {
  try {
    const userId = req.user?.id; const { id } = req.params;
    const med = db.prepare('SELECT id FROM medications WHERE id = ? AND user_id = ?').get(id, userId);
    if (!med) return res.status(404).json({ error: 'Medication not found' });
    const { schedule, frequencyPerDay, isForever, startDate, endDate, daysOfWeek, timezone, reminderEnabled = true } = req.body;
    if (!schedule) return res.status(400).json({ error: 'schedule required' });
    const schedId = randomUUID();
    db.prepare(`INSERT INTO medication_schedules (id, medication_id, schedule, frequency_per_day, is_forever, start_date, end_date, days_of_week, timezone, reminder_enabled)
      VALUES (?,?,?,?,?,?,?,?,?,?)`).run(schedId, id, schedule, frequencyPerDay ?? null, isForever ? 1 : 0, startDate ?? null, endDate ?? null, daysOfWeek ?? null, timezone ?? null, reminderEnabled ? 1 : 0);
    res.json({ id: schedId });
  } catch (e) {
    logger.error('Error creating schedule', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update schedule
router.put('/api/schedules/:scheduleId', (req: Request, res: Response) => {
  try {
    const { scheduleId } = req.params;
    const { schedule, frequencyPerDay, isForever, startDate, endDate, daysOfWeek, timezone, reminderEnabled } = req.body;
    const stmt = db.prepare(`UPDATE medication_schedules SET 
      schedule = COALESCE(?, schedule),
      frequency_per_day = COALESCE(?, frequency_per_day),
      is_forever = COALESCE(?, is_forever),
      start_date = COALESCE(?, start_date),
      end_date = COALESCE(?, end_date),
      days_of_week = COALESCE(?, days_of_week),
      timezone = COALESCE(?, timezone),
      reminder_enabled = COALESCE(?, reminder_enabled)
      WHERE id = ?`);
    const info = stmt.run(schedule ?? null, frequencyPerDay ?? null, typeof isForever === 'boolean' ? (isForever ? 1 : 0) : null, startDate ?? null, endDate ?? null, daysOfWeek ?? null, timezone ?? null, typeof reminderEnabled === 'boolean' ? (reminderEnabled ? 1 : 0) : null, scheduleId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error updating schedule', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete schedule (cascade times via FK)
router.delete('/api/schedules/:scheduleId', (req: Request, res: Response) => {
  try {
    const { scheduleId } = req.params;
    const info = db.prepare('DELETE FROM medication_schedules WHERE id = ?').run(scheduleId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error deleting schedule', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create schedule time
router.post('/api/schedules/:scheduleId/times', (req: Request, res: Response) => {
  try {
    const { scheduleId } = req.params;
    const sched = db.prepare('SELECT id FROM medication_schedules WHERE id = ?').get(scheduleId);
    if (!sched) return res.status(404).json({ error: 'Schedule not found' });
    const { timeLocal, dosage, doseAmount, doseUnit, instructions, prn = false, sortOrder } = req.body;
    if (!timeLocal) return res.status(400).json({ error: 'timeLocal required' });
    const id = randomUUID();
    db.prepare(`INSERT INTO medication_schedule_times (id, schedule_id, time_local, dosage, dose_amount, dose_unit, instructions, prn, sort_order)
      VALUES (?,?,?,?,?,?,?,?,?)`).run(id, scheduleId, timeLocal, dosage ?? null, doseAmount ?? null, doseUnit ?? null, instructions ?? null, prn ? 1 : 0, sortOrder ?? null);
    res.json({ id });
  } catch (e) {
    logger.error('Error creating schedule time', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Update schedule time
router.put('/api/schedule-times/:timeId', (req: Request, res: Response) => {
  try {
    const { timeId } = req.params;
    const { timeLocal, dosage, doseAmount, doseUnit, instructions, prn, sortOrder, nextTriggerTs } = req.body;
    const stmt = db.prepare(`UPDATE medication_schedule_times SET 
      time_local = COALESCE(?, time_local),
      dosage = COALESCE(?, dosage),
      dose_amount = COALESCE(?, dose_amount),
      dose_unit = COALESCE(?, dose_unit),
      instructions = COALESCE(?, instructions),
      prn = COALESCE(?, prn),
      sort_order = COALESCE(?, sort_order),
      next_trigger_ts = COALESCE(?, next_trigger_ts)
      WHERE id = ?`);
    const info = stmt.run(timeLocal ?? null, dosage ?? null, doseAmount ?? null, doseUnit ?? null, instructions ?? null, typeof prn === 'boolean' ? (prn ? 1 : 0) : null, sortOrder ?? null, nextTriggerTs ?? null, timeId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error updating schedule time', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Delete schedule time
router.delete('/api/schedule-times/:timeId', (req: Request, res: Response) => {
  try {
    const { timeId } = req.params;
    const info = db.prepare('DELETE FROM medication_schedule_times WHERE id = ?').run(timeId);
    if (info.changes === 0) return res.status(404).json({ error: 'Not found' });
    res.json({ success: true });
  } catch (e) {
    logger.error('Error deleting schedule time', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// List schedule times for a schedule
router.get('/api/schedules/:scheduleId/times', (req: Request, res: Response) => {
  try {
    const { scheduleId } = req.params;
    const sched = db.prepare('SELECT id FROM medication_schedules WHERE id = ?').get(scheduleId);
    if (!sched) return res.status(404).json({ error: 'Schedule not found' });
    const rows = db.prepare('SELECT * FROM medication_schedule_times WHERE schedule_id = ? ORDER BY sort_order ASC, time_local ASC').all(scheduleId);
    res.json(rows);
  } catch (e) {
    logger.error('Error listing schedule times', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create intake log
router.post('/api/schedule-times/:timeId/intake-logs', (req: Request, res: Response) => {
  try {
    const { timeId } = req.params; const { status, actualDoseAmount, actualDoseUnit, notes } = req.body;
    if (!status) return res.status(400).json({ error: 'status required' });
    const exists = db.prepare('SELECT id FROM medication_schedule_times WHERE id = ?').get(timeId);
    if (!exists) return res.status(404).json({ error: 'Schedule time not found' });
    const id = randomUUID();
    const takenTs = Date.now();
    db.prepare(`INSERT INTO medication_intake_logs (id, schedule_time_id, taken_ts, status, actual_dose_amount, actual_dose_unit, notes)
      VALUES (?,?,?,?,?,?,?)`).run(id, timeId, takenTs, status, actualDoseAmount ?? null, actualDoseUnit ?? null, notes ?? null);
    res.json({ id, takenTs });
  } catch (e) {
    logger.error('Error creating intake log', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// List intake logs for medication
router.get('/api/medications/:id/intake-logs', (req: Request, res: Response) => {
  try {
    const { id } = req.params; const from = req.query.from ? parseInt(req.query.from as string) : undefined; const to = req.query.to ? parseInt(req.query.to as string) : undefined;
    const where: string[] = ['ms.medication_id = ?']; const args:any[] = [id];
    if (from) { where.push('mil.taken_ts >= ?'); args.push(from); }
    if (to) { where.push('mil.taken_ts <= ?'); args.push(to); }
    const rows = db.prepare(`SELECT mil.* FROM medication_intake_logs mil
      JOIN medication_schedule_times mst ON mil.schedule_time_id = mst.id
      JOIN medication_schedules ms ON mst.schedule_id = ms.id
      WHERE ${where.join(' AND ')} ORDER BY mil.taken_ts DESC`).all(...args);
    res.json(rows);
  } catch (e) {
    logger.error('Error listing intake logs', e);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create external user endpoint for device contacts
router.post('/api/users/external', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const { name, email, phone, isExternal } = req.body;
    if (!name || (!email && !phone)) {
      return res.status(400).json({ error: 'Name and either email or phone required' });
    }

    // Use email or create a unique identifier for phone-only contacts
    const identifier = email || `${phone}@phone.local`;
    
    // Check if user already exists
    const existing = db.prepare('SELECT * FROM users WHERE email = ?').get(identifier);
    if (existing) {
      return res.json(existing);
    }

    // Create new external user
    const id = randomUUID();
    db.prepare(`
      INSERT INTO users (id, name, email, phone, photo_url, is_external) 
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(id, name, identifier, phone || null, null, isExternal ? 1 : 0);

    const newUser = db.prepare('SELECT * FROM users WHERE id = ?').get(id);
    res.json(newUser);
  } catch (error) {
    logger.error('Error creating external user:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Runtime debug flags (can be toggled without restart)
const runtimeDebug: { db:boolean; ai:boolean } = {
  db: process.env.DEBUG_DB === '1',
  ai: process.env.DEBUG_AI === '1',
};
// Simplified: canonical messages schema only (profile_id, no conversation_id)
function insertMessageRecord({ id, profileId, userId, role, content, createdAt, processed = 0 }: { id:string; profileId:string; userId:string; role:string; content:string; createdAt:number; processed?:number; }) {
  try {
    db.prepare('INSERT INTO messages (id, profile_id, sender_id, role, content, created_at, processed) VALUES (?,?,?,?,?,?,?)')
      .run(id, profileId, userId, role, content, createdAt, processed);
  } catch (e) {
    const err: any = e;
    logger.error('Error inserting message', { message: err?.message, error: err, stack: err?.stack });
    try {
      const existingProfile = db.prepare('SELECT id FROM profiles WHERE id = ?').get(profileId);
      const existingUser = db.prepare('SELECT id FROM users WHERE id = ?').get(userId);
      logger.error('Foreign key failure inserting message', { profileId, userId, hasProfile: !!existingProfile, hasUser: !!existingUser });
    } catch {}
    throw err;
  }
}

// Instrument sqlite wrapper lazily (only once)
const _origPrepare = (db as any).prepare.bind(db);
(db as any).prepare = function(sql: string) {
  const stmt = _origPrepare(sql);
  if (!stmt || typeof stmt !== 'object') return stmt;
  const origRun = stmt.run?.bind(stmt);
  const origAll = stmt.all?.bind(stmt);
  const origGet = stmt.get?.bind(stmt);
  if (origRun) stmt.run = function(...args: any[]) {
    const start = Date.now();
    try { return origRun(...args); } finally { if (runtimeDebug.db) logger.debug('db.run', { sql: trimSql(sql), ms: Date.now()-start, args }); }
  };
  if (origAll) stmt.all = function(...args: any[]) {
    const start = Date.now();
    const res = origAll(...args);
    if (runtimeDebug.db) logger.debug('db.all', { sql: trimSql(sql), ms: Date.now()-start, args, rows: Array.isArray(res)? res.length: undefined });
    return res;
  };
  if (origGet) stmt.get = function(...args: any[]) {
    const start = Date.now();
    const res = origGet(...args);
    if (runtimeDebug.db) logger.debug('db.get', { sql: trimSql(sql), ms: Date.now()-start, args, hit: !!res });
    return res;
  };
  return stmt;
};

function trimSql(s: string) { return s.replace(/\s+/g,' ').trim().slice(0,160); }

router.get('/api/debug/flags', (_req, res)=> {
  res.json(runtimeDebug);
});

router.post('/api/debug/flags', (req, res)=> {
  const { db, ai } = req.body || {};
  if (typeof db === 'boolean') runtimeDebug.db = db;
  if (typeof ai === 'boolean') runtimeDebug.ai = ai;
  logger.info('Runtime debug flags updated', { runtimeDebug });
  res.json(runtimeDebug);
});

// to the closest health parameter(s) defined in param_targets.
interface ParamTargetRow { param_code: string; target_min?: number|null; target_max?: number|null; preferred_unit?: string|null; description?: string|null; notes?: string|null; organ_system?: string|null; }

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9%\s]/g, ' ')
    .split(/\s+/)
    .filter(t => t.length > 1 && !STOP_WORDS.has(t));
}

const STOP_WORDS = new Set(['the','a','an','of','and','or','to','is','for','with','on','in','at','by','be','as','it','that','this']);
const SYNONYMS: Record<string,string> = {
  sugar: 'glucose',
  bp: 'bloodpressure',
  blood: 'blood',
  pressure: 'pressure',
  a1c: 'hba1c'
};

function normalizeToken(t: string): string {
  return SYNONYMS[t] || t;
}

function buildVector(tokens: string[]): Map<string, number> {
  const m = new Map<string, number>();
  for (const raw of tokens) {
    const t = normalizeToken(raw);
    m.set(t, (m.get(t) || 0) + 1);
  }
  return m;
}

function cosine(a: Map<string, number>, b: Map<string, number>): number {
  let dot = 0; let normA = 0; let normB = 0;
  for (const v of a.values()) normA += v * v;
  for (const v of b.values()) normB += v * v;
  const smaller = a.size < b.size ? a : b;
  const larger = a.size < b.size ? b : a;
  for (const [k,v] of smaller.entries()) {
    const vb = larger.get(k);
    if (vb) dot += v * vb;
  }
  if (!dot || !normA || !normB) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

function matchParamTargets(message: string, limit = 5) {
  // Build or reuse cached vectors for param_targets to avoid O(N) tokenization every request
  const globalAny: any = globalThis as any;
  if (!globalAny.__paramTargetVecCache) {
    const stmt = db.prepare('SELECT param_code, target_min, target_max, preferred_unit, description, notes, organ_system FROM param_targets');
    const rows = (stmt.all() as unknown) as ParamTargetRow[];
    const cache: any[] = [];
    for (const r of rows) {
      const text = [r.param_code, r.description, r.notes, r.organ_system].filter(Boolean).join(' ');
      cache.push({ row: r, vec: buildVector(tokenize(text)) });
    }
    globalAny.__paramTargetVecCache = { ts: Date.now(), items: cache, count: cache.length };
  } else if (Date.now() - globalAny.__paramTargetVecCache.ts > 5 * 60 * 1000) { // Refresh every 5 minutes
    try {
      const stmt = db.prepare('SELECT param_code, target_min, target_max, preferred_unit, description, notes, organ_system FROM param_targets');
      const rows = (stmt.all() as unknown) as ParamTargetRow[];
      const cache: any[] = [];
      for (const r of rows) {
        const text = [r.param_code, r.description, r.notes, r.organ_system].filter(Boolean).join(' ');
        cache.push({ row: r, vec: buildVector(tokenize(text)) });
      }
      globalAny.__paramTargetVecCache = { ts: Date.now(), items: cache, count: cache.length };
    } catch {}
  }
  const cacheItems = globalAny.__paramTargetVecCache.items as { row: ParamTargetRow; vec: Map<string, number>; }[];
  const msgVec = buildVector(tokenize(message));
  const scored = cacheItems.map(ci => ({ row: ci.row, score: cosine(msgVec, ci.vec) }))
    .filter(s => s.score > 0)
    .sort((a,b)=> b.score - a.score)
    .slice(0, limit);
  return scored.map(s => ({
      param_code: s.row.param_code,
      score: Number(s.score.toFixed(4)),
      target_min: s.row.target_min,
      target_max: s.row.target_max,
      preferred_unit: s.row.preferred_unit,
      description: s.row.description,
    }));
}

// Utility
function upsertUser(email: string, name?: string, photoUrl?: string) {
  const existing = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
  if (existing) return existing;
  const id = randomUUID();
  db.prepare('INSERT INTO users (id, name, email, photo_url) VALUES (?, ?, ?, ?)').run(id, name || email.split('@')[0], email, photoUrl || null);
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

// Auth Microsoft Exchange - verifies id_token with JWKS then issues signed JWT
router.post('/api/auth/microsoft/exchange', async (req: Request, res: Response) => {
  const { id_token: idToken } = req.body || {};
  if (!idToken) { logger.warn('Microsoft exchange missing id_token'); return res.status(400).json({ error: 'id_token required' }); }
  try {
    const payload: any = await verifyMicrosoftIdToken(idToken);
    if (!payload || !payload.sub) { logger.warn('Microsoft verify missing sub'); return res.status(400).json({ error: 'invalid token' }); }
    const email = payload.email || payload.preferred_username || `${payload.sub}@microsoft`;
    const user: any = upsertUser(email, payload.name, payload.picture);
    const jwt = await signToken({ uid: user.id, email });
    logger.info('Microsoft auth success', { userId: user.id, email });
    res.json({ token: jwt, user });
  } catch (e: any) {
    logger.warn('Microsoft auth verification failed', { error: e.message });
    res.status(400).json({ error: 'verification failed', detail: e.message });
  }
});

// Dev helper: issue token for manual testing (ONLY when NODE_ENV=development)
router.post('/api/auth/dev-login', async (req: Request, res: Response) => {
  if (process.env.NODE_ENV === 'production') { logger.warn('Dev login attempted in production'); return res.status(403).json({ error: 'disabled in production' }); }
  const email = (req.body && req.body.email) || 'devuser@example.com';
  const user: any = upsertUser(email, 'Dev User');
  const jwt = await signToken({ uid: user.id, email });
  logger.info('Dev login issued', { userId: user.id, email });
  res.json({ token: jwt, user });
});

// Authenticated AI interpretation endpoint (after dev-login or ms auth)
router.post('/api/ai/interpret', async (req: Request, res: Response) => {
  const { message } = req.body || {};
  if (!message) { logger.warn('Interpret endpoint missing message'); return res.status(400).json({ error: 'message required' }); }
  if (runtimeDebug.ai) logger.debug('ai.interpret.req', { message });
  const result = await interpretMessage(String(message));
  logger.info('AI interpret (no store)', { reqId: (req as any).reqId, parsed: result.parsed, type: result.entry?.type, vitalType: result.entry?.vital?.vitalType });
  const matches = matchParamTargets(String(message), 5);
  if (runtimeDebug.ai) logger.debug('ai.interpret.res', { parsed: result.parsed, entry: result.entry, matches });
  res.json({ ...result, matches });
});

// Public status (no secrets) to help debug AI config
router.get('/api/ai/status', (_req: Request, res: Response) => {
  res.json(aiProviderStatus());
});

// Debug endpoint to reload prompts from files
router.post('/api/ai/reload-prompts', (_req: Request, res: Response) => {
  try {
    clearPromptCache();
    logger.info('Prompt cache cleared');
    
    // Validate prompts by loading them
    const entryPrompt = getHealthDataEntryPrompt();
    const trendPrompt = getHealthDataTrendPrompt();
    res.json({ 
      success: true, 
      message: 'Prompts reloaded successfully',
      entryPromptLength: entryPrompt.length,
      trendPromptLength: trendPrompt.length
    });
  } catch (error: any) {
    res.status(500).json({ 
      success: false, 
      error: 'Failed to reload prompts', 
      detail: error.message 
    });
  }
});

// --- Simple in-memory vector search over param_targets (bag-of-words cosine) ---
// This avoids external dependencies while enabling approximate semantic mapping of a user message
// to the closest health parameter(s) defined in param_targets.
function parseSimpleHealthMessage(message: string, userId: string = 'prototype-user-12345'): any | null {
  const lower = message.toLowerCase().trim();
  
  // Blood sugar patterns: "224 post lunch sugar", "sugar 150", "glucose 120 mg/dl"
  let match = /(\d{2,3})\s*(?:post\s*lunch\s*|after\s*meal\s*|fasting\s*)?(?:sugar|glucose|blood\s*sugar)(?:\s*(\d{2,3})\s*mg\/dl)?/i.exec(message);
  if (!match) {
    match = /(?:sugar|glucose|blood\s*sugar)[\s:]*(\d{2,3})(?:\s*mg\/dl)?/i.exec(message);
  }
  if (!match) {
    match = /(\d{2,3})(?:\s*mg\/dl)?\s*(?:sugar|glucose)/i.exec(message);
  }
  
  if (match) {
    const value = match[1];
    const numValue = parseInt(value, 10);
    if (numValue >= 50 && numValue <= 500) { // Reasonable blood sugar range
      const notes = lower.includes('lunch') ? 'post lunch' : 
                   lower.includes('meal') ? 'after meal' :
                   lower.includes('fasting') ? 'fasting' : null;
      
      return {
        id: randomUUID(),
        user_id: userId,
        type: 'BLOOD_SUGAR',
        category: 'HEALTH_PARAMS',
        value: value,
        quantity: null,
        unit: 'mg/dL',
        timestamp: Math.floor(Date.now() / 1000),
        notes: notes,
      };
    }
  }
  
  // Blood pressure patterns: "120/80", "bp 130 over 85"
  match = /(\d{2,3})[\s/](?:over\s*)?(\d{2,3})(?:\s*mmhg)?/i.exec(message);
  if (match && (lower.includes('bp') || lower.includes('blood pressure') || lower.includes('pressure'))) {
    const systolic = parseInt(match[1], 10);
    const diastolic = parseInt(match[2], 10);
    if (systolic >= 70 && systolic <= 250 && diastolic >= 40 && diastolic <= 150) {
      return {
        id: randomUUID(),
        user_id: userId,
        type: 'BLOOD_PRESSURE',
        category: 'VITALS',
        value: `${systolic}/${diastolic}`,
        quantity: null,
        unit: 'mmHg',
        timestamp: Math.floor(Date.now() / 1000),
        notes: null,
      };
    }
  }
  
  return null;
}

// New endpoint: Process message with health data entry prompt
router.post('/api/ai/process-with-prompt', async (req: Request, res: Response) => {
  const { message } = req.body || {};
  if (!message) {
    return res.status(400).json({ error: 'message required' });
  }

  const userId = (req as any).userId || 'prototype-user-12345';

  try {
    logger.debug('Processing message with health data entry prompt', { message });

    // Step 1: Save user message to messages table immediately
    const userMessageId = randomUUID();
    const createdAt = Date.now();
    
  insertMessageRecord({ id: userMessageId, profileId: 'me-conversation', userId, role: 'user', content: String(message), createdAt, processed: 0 });
    
    logger.debug('Saved user message to messages table', { messageId: userMessageId });
    
    // Create a custom AI call specifically for the health data format
    const ollamaBase = process.env.OLLAMA_BASE_URL;
    const ollamaModel = process.env.OLLAMA_MODEL || 'mistral-openorca:latest';
    
    if (!ollamaBase) {
      return res.status(500).json({ error: 'AI not configured', detail: 'OLLAMA_BASE_URL missing' });
    }

    // Get the health data entry prompt
    const prompt = getHealthDataEntryPrompt();
    
    // Call Ollama directly with the health data prompt
    const messages = [
      { role: 'system', content: prompt },
      { role: 'user', content: String(message) }
    ];

    const url = `${ollamaBase.replace(/\/$/, '')}/api/chat`;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000); // Reduced timeout

    try {
      const resp = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: controller.signal,
        body: JSON.stringify({
          model: ollamaModel,
          stream: false,
          messages,
          options: {
            temperature: 0,
            top_p: 0.9,
          }
        })
      });
      
      clearTimeout(timeoutId);
      
      if (!resp.ok) {
        throw new Error(`Ollama error ${resp.status}`);
      }
      
      const json = await resp.json();
      const content = json.message?.content || '';
      
      logger.debug('Raw AI response', { content: content.slice(0, 500) });
      
      // Try to extract JSON from the response
      let healthData = null;
      let reply = 'Message processed';
      
      try {
        // Look for JSON in the response - try multiple approaches
        let jsonStr = '';
        
        // Approach 1: Look for complete JSON object
        const jsonStart = content.indexOf('{');
        const jsonEnd = content.lastIndexOf('}');
        
        if (jsonStart !== -1 && jsonEnd !== -1 && jsonEnd > jsonStart) {
          jsonStr = content.substring(jsonStart, jsonEnd + 1);
        } else {
          // Approach 2: Try to find JSON-like content with regex
          const jsonMatch = content.match(/\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/);
          if (jsonMatch) {
            jsonStr = jsonMatch[0];
          }
        }
        
        if (jsonStr) {
          const parsed = JSON.parse(jsonStr);
          logger.debug('Parsed AI JSON response', { parsed });
          
          // Validate that it has the expected health_data fields
          if (parsed.type) {
            const userId = (req as any).userId || 'prototype-user-12345'; // Use the actual user ID from middleware
            healthData = {
              id: randomUUID(), // Always generate a new UUID instead of using AI-generated ID
              user_id: userId, // Use the actual user ID instead of the AI-generated one
              type: parsed.type,
              category: parsed.category || 'HEALTH_PARAMS',
              value: parsed.value || null,
              quantity: parsed.quantity || null,
              unit: parsed.unit || null,
              timestamp: parsed.timestamp || Math.floor(Date.now() / 1000),
              notes: parsed.notes || null,
            };
            reply = 'Health data extracted successfully';
            logger.info('Successfully extracted health data from AI response', { type: parsed.type, value: parsed.value });
          } else {
            logger.warn('AI response missing required type field', { parsed });
          }
        } else {
          logger.warn('No JSON found in AI response', { content: content.slice(0, 200) });
        }
      } catch (parseError) {
        logger.warn('Failed to parse AI JSON response', { error: parseError, content: content.slice(0, 200) });
      }
      
      // If no structured data was extracted, try the fallback approach
      if (!healthData) {
        logger.warn('Direct prompt parsing failed, trying interpretMessage fallback');
        // Use the existing interpretMessage as fallback
        const fallbackResult = await interpretMessage(String(message));
        if (fallbackResult.parsed && fallbackResult.entry) {
          const entry = fallbackResult.entry;
          const timestamp = entry.timestamp || Date.now();
          
          if (entry.type === 'vital' && entry.vital) {
            const vital = entry.vital;
            let value = null;
            let unit = vital.unit || null;
            
            if (vital.vitalType === 'bloodPressure' && vital.systolic && vital.diastolic) {
              value = `${vital.systolic}/${vital.diastolic}`;
              unit = unit || 'mmHg';
            } else if (vital.value != null) {
              value = String(vital.value);
            }
            
            const userId = (req as any).userId || 'prototype-user-12345';
            healthData = {
              id: randomUUID(),
              user_id: userId,
              type: vital.vitalType?.toUpperCase() || 'GLUCOSE',
              category: entry.category || 'HEALTH_PARAMS',
              value,
              quantity: null,
              unit,
              timestamp: Math.floor(timestamp / 1000),
              notes: null,
            };
            reply = fallbackResult.reply || 'Health data processed via fallback';
          }
        }
      }
      
      // Step 2: Save AI response to messages table
      const aiMessageId = randomUUID();
      const aiResponse = reply || 'Health data processed';
      
  insertMessageRecord({ id: aiMessageId, profileId: 'me-profile', userId, role: 'assistant', content: aiResponse, createdAt: Date.now(), processed: 1 });
      
      // Step 3: Update user message as processed and link to health data if extracted
      const interpretation = {
        reply: aiResponse,
        parsed: !!healthData,
        healthData: healthData,
        reasoning: healthData ? null : 'Could not extract structured health data'
      };
      
      const storedRecordId = healthData ? healthData.id : null;
      db.prepare('UPDATE messages SET interpretation_json = ?, processed = 1, stored_record_id = ? WHERE id = ?')
        .run(JSON.stringify(interpretation), storedRecordId, userMessageId);
      
      logger.info('Saved AI response and updated message processing', { 
        userMessageId, 
        aiMessageId, 
        healthDataExtracted: !!healthData,
        storedRecordId 
      });

      res.json({
        reply: aiResponse,
        healthData,
        reasoning: healthData ? null : 'Could not extract structured health data',
        messageId: userMessageId,
        aiMessageId: aiMessageId,
      });
      
    } catch (fetchError: any) {
      clearTimeout(timeoutId);
      logger.warn('Ollama request failed, trying fallback', { error: fetchError.message });
      
      // Fallback to existing interpretMessage function
      try {
        const fallbackResult = await interpretMessage(String(message));
        if (fallbackResult.parsed && fallbackResult.entry) {
          const entry = fallbackResult.entry;
          const timestamp = entry.timestamp || Date.now();
          
          if (entry.type === 'vital' && entry.vital) {
            const vital = entry.vital;
            let value = null;
            let unit = vital.unit || null;
            
            if (vital.vitalType === 'bloodPressure' && vital.systolic && vital.diastolic) {
              value = `${vital.systolic}/${vital.diastolic}`;
              unit = unit || 'mmHg';
            } else if (vital.value != null) {
              value = String(vital.value);
            }
            
            const healthData = {
              id: randomUUID(),
              user_id: 'current_user_id',
              type: vital.vitalType?.toUpperCase() || 'GLUCOSE',
              category: entry.category || 'HEALTH_PARAMS',
              value,
              quantity: null,
              unit,
              timestamp: Math.floor(timestamp / 1000),
              notes: null,
            };
            
            return res.json({
              reply: fallbackResult.reply || 'Health data processed via fallback',
              healthData,
              reasoning: 'Used fallback AI processing',
            });
          } else if (entry.type === 'param' && entry.param) {
            const param = entry.param;
            const userId = (req as any).userId || 'prototype-user-12345';
            const healthData = {
              id: randomUUID(),
              user_id: userId,
              type: param.param_code,
              category: entry.category || 'HEALTH_PARAMS',
              value: param.value != null ? String(param.value) : null,
              quantity: null,
              unit: param.unit || null,
              timestamp: Math.floor(timestamp / 1000),
              notes: param.notes || null,
            };
            
            return res.json({
              reply: fallbackResult.reply || 'Health data processed via fallback',
              healthData,
              reasoning: 'Used fallback AI processing',
            });
          }
        }
      } catch (fallbackError: any) {
        logger.error('Fallback AI processing also failed', { error: fallbackError.message });
      }
      
      // Last resort: simple regex parsing for common patterns
      const userId = (req as any).userId || 'prototype-user-12345';
      const simpleHealthData = parseSimpleHealthMessage(String(message), userId);
      if (simpleHealthData) {
        logger.info('Used simple regex parsing as last resort');
        return res.json({
          reply: 'Health data extracted using simple parsing',
          healthData: simpleHealthData,
          reasoning: 'Used simple regex parsing',
        });
      }
      
      res.status(500).json({ error: 'AI request failed', detail: fetchError.message });
    }
    
  } catch (error: any) {
    logger.error('Process with prompt failed', { error: error.message });
    
    // Try to update the user message as failed if it was created
    try {
      const interpretation = {
        reply: 'Processing failed',
        parsed: false,
        error: error.message,
        reasoning: 'Processing error occurred'
      };
      
      // Find the most recent unprocessed message for this user
      const recentMessage = db.prepare('SELECT id FROM messages WHERE sender_id = ? AND processed = 0 ORDER BY created_at DESC LIMIT 1').get(userId) as { id: string } | undefined;
      if (recentMessage) {
        db.prepare('UPDATE messages SET interpretation_json = ?, processed = 1 WHERE id = ?')
          .run(JSON.stringify(interpretation), recentMessage.id);
      }
    } catch (updateError) {
      logger.warn('Failed to update message with error status', { updateError });
    }
    
    res.status(500).json({ error: 'processing failed', detail: error.message });
  }
});

// New endpoint: Save health data entry
router.post('/api/health-data', (req: Request, res: Response) => {
  const { id, user_id, profile_id, type, category, value, quantity, unit, timestamp, notes } = req.body || {};
  
  if (!id || !user_id || !profile_id || !type || !timestamp) {
    return res.status(400).json({ error: 'id, user_id, profile_id, type, and timestamp are required' });
  }
  
  try {
    // Check if quantity column exists
    const tableInfo = db.prepare('PRAGMA table_info(health_data)').all() as any[];
    const hasQuantity = tableInfo.some((col: any) => col.name === 'quantity');
    
    if (hasQuantity) {
      db.prepare(`
  INSERT INTO health_data (id, user_id, profile_id, type, category, value, quantity, unit, timestamp, notes) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        user_id,
  profile_id,
        type,
        category || 'HEALTH_PARAMS',
        value || null,
        quantity || null,
        unit || null,
        timestamp,
        notes || null
      );
    } else {
      // Fallback for tables without quantity column
      db.prepare(`
  INSERT INTO health_data (id, user_id, profile_id, type, category, value, unit, timestamp, notes) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        user_id,
  profile_id,
        type,
        category || 'HEALTH_PARAMS',
        value || null,
        unit || null,
        timestamp,
        notes || null
      );
    }
    
    const saved = db.prepare('SELECT * FROM health_data WHERE id = ?').get(id);
    res.status(201).json(saved);
  } catch (error: any) {
    logger.error('Save health data failed', { error: error.message });
    res.status(500).json({ error: 'save failed', detail: error.message });
  }
});

// New endpoint: Generate trend analysis
router.post('/api/health-data/trend', (req: Request, res: Response) => {
  const { type, category, userId, limit } = req.body || {};
  
  if (!type || !category || !userId) {
    return res.status(400).json({ error: 'type, category, and userId are required' });
  }
  
  try {
    const dataLimit = Math.min(Number(limit) || 20, 100);
    
    // Query health data for trend analysis
    const rows = db.prepare(`
      SELECT * FROM health_data 
      WHERE user_id = ? AND type = ? AND category = ? 
      ORDER BY timestamp ASC 
      LIMIT ?
    `).all(userId, type, category, dataLimit);
    
    if (!rows || rows.length === 0) {
      return res.json({
        chart: null,
        prognosis: 'No historical data available for this parameter.',
      });
    }
    
    // Simple trend analysis
    const values = rows
      .map((row: any) => parseFloat(row.value))
      .filter((val: number) => !isNaN(val));
    
    if (values.length < 2) {
      return res.json({
        chart: null,
        prognosis: 'Insufficient data points for trend analysis.',
      });
    }
    
    // Calculate basic trend
    const firstValue = values[0];
    const lastValue = values[values.length - 1];
    const trend = lastValue > firstValue ? 'increasing' : lastValue < firstValue ? 'decreasing' : 'stable';
    const changePercent = Math.abs(((lastValue - firstValue) / firstValue) * 100).toFixed(1);
    
    let prognosis = `Your ${type} values show a ${trend} trend over time.`;
    if (trend !== 'stable') {
      prognosis += ` There's been a ${changePercent}% change from your first to most recent reading.`;
    }
    
    // Simple chart data (just the values and timestamps)
    const chartData = rows.map((row: any) => ({
      timestamp: row.timestamp,
      value: parseFloat(row.value) || 0,
      unit: row.unit,
    }));
    
    res.json({
      chart: JSON.stringify(chartData),
      prognosis,
      dataPoints: rows.length,
      trend,
    });
  } catch (error: any) {
    logger.error('Trend analysis failed', { error: error.message });
    res.status(500).json({ error: 'trend analysis failed', detail: error.message });
  }
});

// List distinct health data types for current user (category filter optional)
router.get('/api/health-data/types', (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.id || (req as any).userId;
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    const category = (req.query.category as string) || 'HEALTH_PARAMS';
    const qRaw = (req.query.q as string) || '';
    const limit = Math.min(parseInt((req.query.limit as string) || '50') || 50, 200);
    let rows: any[];
    if (qRaw) {
      const q = `%${qRaw.toLowerCase()}%`;
      rows = db.prepare(`SELECT DISTINCT type FROM health_data WHERE user_id = ? AND (? IS NULL OR category = ?) AND LOWER(type) LIKE ? ORDER BY type ASC LIMIT ?`)
        .all(userId, category, category, q, limit) as any[];
    } else {
      rows = db.prepare(`SELECT DISTINCT type FROM health_data WHERE user_id = ? AND (? IS NULL OR category = ?) ORDER BY type ASC LIMIT ?`)
        .all(userId, category, category, limit) as any[];
    }
    res.json(rows.map(r => r.type));
  } catch (e: any) {
    logger.error('health-data/types failed', { error: e.message });
    res.status(500).json({ error: 'failed' });
  }
});

// Time-series for a given type within range
router.get('/api/health-data/series', (req: Request, res: Response) => {
  try {
    const userId = (req as any).user?.id || (req as any).userId;
    if (!userId) return res.status(401).json({ error: 'unauthorized' });
    const type = req.query.type as string | undefined;
    if (!type) return res.status(400).json({ error: 'type required' });
    const fromMs = Number(req.query.from) || 0;
    const toMs = Number(req.query.to) || Date.now();
    let rows = db.prepare('SELECT timestamp, value, unit FROM health_data WHERE user_id = ? AND type = ? AND timestamp BETWEEN ? AND ? ORDER BY timestamp ASC')
      .all(userId, type, fromMs, toMs) as any[];
    // Fallback alias: some older entries may have used 'glucose' vs 'GLU_FAST'
    if (!rows.length && type === 'GLU_FAST') {
      rows = db.prepare("SELECT timestamp, value, unit FROM health_data WHERE user_id = ? AND type IN ('GLU_FAST','glucose') AND timestamp BETWEEN ? AND ? ORDER BY timestamp ASC")
        .all(userId, fromMs, toMs) as any[];
    }
    const cleaned = rows.map(r => ({ timestamp: r.timestamp, value: r.value, unit: r.unit }));
    res.json(cleaned);
  } catch (e:any) {
    logger.error('health-data/series failed', { error: e.message });
    res.status(500).json({ error: 'failed' });
  }
});

// AI interpret + persist (requires auth). This does not change existing provisional local insert logic on the client;
// it offers a backend mapping path so the AI output becomes a stored row.
router.post('/api/ai/interpret-store', async (req: Request, res: Response) => {
  const { message, profile_id } = req.body || {};
  if (!message) { logger.warn('Interpret-store missing message'); return res.status(400).json({ error: 'message required' }); }
  const userId = (req as any).user?.id || (req as any).userId;
  logger.debug('Interpret-store userId check', { userId, hasUserId: !!userId, type: typeof userId });

  const profileId = profile_id || 'default-profile';
  // Store raw message first
  const msgId = randomUUID();
  const createdAt = Date.now();
  insertMessageRecord({ id: msgId, profileId, userId, role: 'user', content: String(message), createdAt, processed: 0 });
  const interpretation = await interpretMessage(String(message));
  const matches = matchParamTargets(String(message), 5);
  if (runtimeDebug.ai) logger.debug('ai.interpretStore.res', { parsed: interpretation.parsed, entry: interpretation.entry, matches });
  if (!interpretation.parsed || !interpretation.entry) {
    logger.info('Interpret-store no parsed entry', { reqId: (req as any).reqId, parsed: interpretation.parsed });
    db.prepare('UPDATE messages SET interpretation_json = ?, processed = 1 WHERE id = ?')
      .run(JSON.stringify(interpretation), msgId);
    return res.status(200).json({ interpretation, stored: null, messageId: msgId, matches });
  }
  try {
  const stored = persistAiEntry(interpretation.entry, userId, profileId);
    db.prepare('UPDATE messages SET interpretation_json = ?, processed = 1, stored_record_id = ? WHERE id = ?')
      .run(JSON.stringify(interpretation), stored.id, msgId);
    logger.info('Persisted AI entry', { reqId: (req as any).reqId, storedType: stored.type || stored.name, id: stored.id });
    return res.status(201).json({ interpretation, stored, storedId: stored.id, storedType: stored.type || stored.name, messageId: msgId, matches });
  } catch (e: any) {
    logger.error('Persist failed', { error: e.message });
    db.prepare('UPDATE messages SET interpretation_json = ?, processed = 1 WHERE id = ?')
      .run(JSON.stringify({ error: e.message, interpretation }), msgId);
    return res.status(500).json({ error: 'persist failed', detail: e.message, interpretation, matches });
  }
});

// Helper to map AI entry -> DB rows.
function persistAiEntry(entry: NonNullable<AiInterpretation['entry']>, userId: string, profileId: string) {
  const id = randomUUID();
  // Normalize timestamp to milliseconds (AI may occasionally supply seconds epoch)
  let ts = entry.timestamp ?? Date.now();
  if (ts < 1e12) ts = ts * 1000;
  // Safety clamp: if timestamp is >3 days in future or >400 days in past for entries without explicit date flag, reset to now.
  const now = Date.now();
  const ageDays = (now - ts) / 86400000;
  if (ageDays > 400 || ts - now > 3 * 86400000) {
    ts = now;
  }
  const category = entry.category || 'HEALTH_PARAMS';
  
  switch (entry.type) {
    case 'vital': {
      if (!entry.vital || !entry.vital.vitalType) throw new Error('vital.vitalType missing');
      const vt = entry.vital.vitalType;
      let value: string | null = null;
      let unit: string | null = entry.vital.unit || null;
      
      if (vt === 'bloodPressure') {
        const sys = entry.vital.systolic;
        const dia = entry.vital.diastolic;
        if (sys == null || dia == null) throw new Error('bloodPressure requires systolic & diastolic');
        value = `${sys}/${dia}`;
        unit = unit || 'mmHg';
      } else if (entry.vital.value != null) {
        value = String(entry.vital.value);
        // Set default units for common vitals if not provided
        if (!unit) {
          switch (vt) {
            case 'steps': unit = 'steps'; break;
            case 'weight': unit = 'kg'; break;
            case 'glucose': unit = 'mg/dL'; break;
            case 'heartRate': unit = 'bpm'; break;
            case 'temperature': unit = '°C'; break;
            case 'hba1c': unit = '%'; break;
          }
        }
      }
      
      logger.debug('DB insert health_data vital', { vt, value, unit, category, ts });
      db.prepare('INSERT INTO health_data (id, user_id, profile_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, profileId, vt, category, value, unit, ts, null);
      return { table: 'health_data', id, type: vt, category, value, unit, timestamp: ts };
    }
    case 'param': {
      if (!entry.param || !entry.param.param_code) throw new Error('param.param_code missing');
      const p = entry.param;
      const value = p.value != null ? String(p.value) : null;
      const unit = p.unit || null;
      const notes = p.notes || null;
      logger.debug('DB insert param as health_data', { code: p.param_code, value, unit, category, ts });
      db.prepare('INSERT INTO health_data (id, user_id, profile_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, profileId, p.param_code, category, value, unit, ts, notes);
      return { table: 'health_data', id, type: p.param_code, category, value, unit, notes, timestamp: ts };
    }
    case 'note': {
      const noteId = id;
      const noteText = entry.note || '';
      logger.debug('DB insert note', { category, ts });
      db.prepare('INSERT INTO health_data (id, user_id, profile_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(noteId, userId, profileId, 'note', category, null, null, ts, noteText);
      return { table: 'health_data', id: noteId, type: 'note', category, notes: noteText, timestamp: ts };
    }
    case 'medication': {
      if (!entry.medication || !entry.medication.name) throw new Error('medication.name missing');
      const m = entry.medication;
      const dosageParts: string[] = [];
      if (m.dose != null) dosageParts.push(String(m.dose));
      if (m.doseUnit) dosageParts.push(m.doseUnit);
      const dosage = dosageParts.join(' '); // e.g., "500 mg"
      let schedule: string | null = null;
      if (m.frequencyPerDay) schedule = `${m.frequencyPerDay}x/day`;
      logger.debug('DB insert medication', { name: m.name, dosage, schedule, duration: m.durationDays, profileId });
      db.prepare('INSERT INTO medications (id, user_id, profile_id, name, dosage, schedule, duration_days, is_forever, start_date) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, profileId, m.name, dosage || null, schedule, m.durationDays ?? null, 0, ts);
      return { table: 'medications', id, name: m.name, dosage: dosage || null, schedule, durationDays: m.durationDays ?? null, startDate: ts };
    }
    case 'labResult': {
      // Schema does not yet enumerate structured labResult fields in AI output; store raw entry JSON.
      const noteId = id;
      const serialized = JSON.stringify(entry);
      logger.debug('DB insert labResult', { category, length: serialized.length });
      db.prepare('INSERT INTO health_data (id, user_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?)')
        .run(noteId, userId, 'labResult', category, null, null, ts, serialized);
      return { table: 'health_data', id: noteId, type: 'labResult', category, raw: serialized, timestamp: ts };
    }
    case 'activity': {
      if (!entry.activity || !entry.activity.name) throw new Error('activity.name missing');
      const a = entry.activity;
      logger.debug('DB insert activity', { name: a.name, distance: a.distance_km, duration: a.duration_minutes, intensity: a.intensity, profileId });
      db.prepare('INSERT INTO activities (id, user_id, profile_id, name, duration_minutes, distance_km, intensity, calories_burned, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?,?)')
        .run(id, userId, profileId, a.name, a.duration_minutes ?? null, a.distance_km ?? null, a.intensity ?? null, a.calories_burned ?? null, ts, a.notes ?? null);
      return { table: 'activities', id, name: a.name, duration_minutes: a.duration_minutes ?? null, distance_km: a.distance_km ?? null, intensity: a.intensity ?? null, calories_burned: a.calories_burned ?? null, timestamp: ts, notes: a.notes ?? null };
    }
    default:
      throw new Error(`Unsupported entry.type: ${entry.type}`);
  }
}

// Validation schemas
const healthDataSchema = z.object({
  type: z.string(),
  category: z.enum(['HEALTH_PARAMS','ACTIVITY','FOOD','MEDICATION','SYMPTOMS','OTHER']).optional(),
  value: z.string().optional(),
  unit: z.string().optional(),
  timestamp: z.number().int().optional(),
  notes: z.string().optional(),
  profile_id: z.string().optional(),
});

router.post('/api/health', (req: Request, res: Response) => {
  const parsed = healthDataSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const id = randomUUID();
  const userId = (req as any).userId;
  const { type, category, value, unit, timestamp, notes, profile_id } = parsed.data;
  // Normalize to ms epoch; accept seconds and convert
  let ts = timestamp ?? Date.now();
  if (ts < 1e12) ts = ts * 1000;
  const cat = category || 'HEALTH_PARAMS';
  const profId = profile_id || 'default-profile';
  db.prepare('INSERT INTO health_data (id, user_id, profile_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
    .run(id, userId, profId, type, cat, value || null, unit || null, ts, notes || null);
  res.status(201).json({ id, type, category: cat, value, unit, timestamp: ts, notes, profile_id: profId });
});

router.get('/api/health', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const limit = Math.min(Number(req.query.limit || 50), 500);
  const offset = Number(req.query.offset || 0);
  const type = req.query.type as string | undefined;
  const start = req.query.start ? Number(req.query.start) : undefined;
  const end = req.query.end ? Number(req.query.end) : undefined;
  let sql = 'SELECT * FROM health_data WHERE user_id = ?';
  const params: any[] = [userId];
  if (type) { sql += ' AND type = ?'; params.push(type); }
  if (start) { sql += ' AND timestamp >= ?'; params.push(start); }
  if (end) { sql += ' AND timestamp <= ?'; params.push(end); }
  sql += ' ORDER BY timestamp DESC LIMIT ? OFFSET ?';
  params.push(limit, offset);
  const rows = db.prepare(sql).all(...params);
  res.json({ items: rows, paging: { limit, offset, count: rows.length } });
});

router.get('/api/health/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const row = db.prepare('SELECT * FROM health_data WHERE id = ? AND user_id = ?').get(req.params.id, userId);
  if (!row) return res.status(404).json({ error: 'not found' });
  res.json(row);
});

router.delete('/api/health/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const info = db.prepare('DELETE FROM health_data WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Activities CRUD
const activityCreateSchema = z.object({
  id: z.string().optional(),
  profile_id: z.string().optional(),
  name: z.string().min(1),
  duration_minutes: z.number().int().optional(),
  distance_km: z.number().optional(),
  intensity: z.string().optional(),
  calories_burned: z.number().optional(),
  timestamp: z.number().optional(), // epoch ms or seconds
  notes: z.string().optional(),
});

router.post('/api/activities', (req: Request, res: Response) => {
  const p = activityCreateSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: p.error.flatten() });
  const userId = (req as any).userId;
  const id = p.data.id || randomUUID();
  const profileId = p.data.profile_id || 'default-profile';
  let ts = p.data.timestamp ?? Date.now();
  if (ts < 1e12) ts = ts * 1000; // seconds -> ms
  db.prepare('INSERT INTO activities (id, user_id, profile_id, name, duration_minutes, distance_km, intensity, calories_burned, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?,?)')
    .run(id, userId, profileId, p.data.name, p.data.duration_minutes ?? null, p.data.distance_km ?? null, p.data.intensity ?? null, p.data.calories_burned ?? null, ts, p.data.notes ?? null);
  res.status(201).json({
    id,
    user_id: userId,
    profile_id: profileId,
    name: p.data.name,
    duration_minutes: p.data.duration_minutes ?? null,
    distance_km: p.data.distance_km ?? null,
    intensity: p.data.intensity ?? null,
    calories_burned: p.data.calories_burned ?? null,
    timestamp: ts,
    notes: p.data.notes ?? null,
  });
});

router.get('/api/activities', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const limit = Math.min(Number(req.query.limit || 50), 500);
  const offset = Number(req.query.offset || 0);
  const start = req.query.start ? Number(req.query.start) : undefined;
  const end = req.query.end ? Number(req.query.end) : undefined;
  
  let sql = 'SELECT * FROM activities WHERE user_id = ?';
  const params: any[] = [userId];
  if (start) { sql += ' AND timestamp >= ?'; params.push(start); }
  if (end) { sql += ' AND timestamp <= ?'; params.push(end); }
  sql += ' ORDER BY timestamp DESC LIMIT ? OFFSET ?';
  params.push(limit, offset);
  
  const rows = db.prepare(sql).all(...params);
  res.json({ items: rows, paging: { limit, offset, count: rows.length } });
});

router.get('/api/activities/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const row = db.prepare('SELECT * FROM activities WHERE id = ? AND user_id = ?').get(req.params.id, userId);
  if (!row) return res.status(404).json({ error: 'not found' });
  res.json(row);
});

router.delete('/api/activities/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const info = db.prepare('DELETE FROM activities WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});


// Reports CRUD
const reportSchema = z.object({
  id: z.string().optional(),
  user_id: z.string().optional(),
  profile_id: z.string().nullable().optional(),
  file_path: z.string(),
  file_type: z.string().optional(), // frontend sends 'file_type'
  type: z.string().optional(), // also accept 'type' for compatibility
  source: z.string().optional(), // frontend sends 'source'
  ai_summary: z.string().nullable().optional(),
  created_at: z.union([z.string(), z.number()]).optional(), // accept both string and number
  upload_date: z.number().int().optional(), // also accept 'upload_date' as number
  parsed: z.number().or(z.boolean()).optional(), // frontend sends 'parsed'
});

router.post('/api/reports', (req: Request, res: Response) => {
  const p = reportSchema.safeParse(req.body);
  if (!p.success) {
    logger.error('Report validation failed', { error: p.error.flatten(), body: req.body });
    return res.status(400).json({ error: p.error.flatten() });
  }
  const userId = (req as any).user?.id || (req as any).userId;
  const reportId = p.data.id || randomUUID();
  const { profile_id, file_path, ai_summary } = p.data;
  
  // Handle both file_type and type fields
  const fileType = p.data.file_type || p.data.type || 'unknown';
  const source = p.data.source || 'upload';
  
  // Handle both created_at and upload_date fields
  let timestamp: number;
  if (p.data.created_at) {
    // Handle both number (timestamp) and string (ISO) formats
    if (typeof p.data.created_at === 'number') {
      timestamp = p.data.created_at;
    } else {
      timestamp = new Date(p.data.created_at).getTime();
    }
  } else if (p.data.upload_date) {
    timestamp = p.data.upload_date;
  } else {
    timestamp = Date.now();
  }
  
  // profile_id is required by database, use default if not provided
  const profileId = profile_id || 'default-profile';
  
  try {
    db.prepare(`INSERT INTO reports 
      (id, user_id, profile_id, file_path, file_type, source, ai_summary, created_at, parsed) 
      VALUES (?,?,?,?,?,?,?,?,?)`)
      .run(reportId, userId, profileId, file_path, fileType, source, ai_summary || null, timestamp, 0);
    
    res.status(201).json({ 
      id: reportId, 
      user_id: userId,
  profile_id: profileId,
      file_path, 
      file_type: fileType, // return as file_type for frontend
      type: fileType, // also include for compatibility
      source: source,
      ai_summary: ai_summary || null,
      created_at: new Date(timestamp).toISOString(), // return as ISO string for frontend
      upload_date: timestamp, // also include for compatibility
      parsed: 0
    });
  } catch (error) {
    logger.error('Database error creating report', { error, reportId, userId });
    res.status(500).json({ error: 'Failed to create report' });
  }
});

router.get('/api/reports', (req: Request, res: Response) => {
  const userId = (req as any).user?.id || (req as any).userId;
  const file_type = req.query.file_type as string | undefined;
  let sql = 'SELECT * FROM reports WHERE user_id = ?';
  const params: any[] = [userId];
  if (file_type) { sql += ' AND file_type = ?'; params.push(file_type); }
  sql += ' ORDER BY created_at DESC';
  const rows = db.prepare(sql).all(...params);
  
  // Map database field names to frontend field names for compatibility
  const mappedRows = rows.map((report: any) => ({
    ...report,
    created_at: new Date(report.created_at).toISOString(), // convert timestamp to ISO string
    upload_date: report.created_at, // keep original timestamp for compatibility
  }));
  
  res.json(mappedRows);
});

router.delete('/api/reports/:id', (req: Request, res: Response) => {
  const userId = (req as any).user?.id || (req as any).userId;
  const info = db.prepare('DELETE FROM reports WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Get single report
router.get('/api/reports/:id', (req: Request, res: Response) => {
  const userId = (req as any).user?.id || (req as any).userId;
  const row = db.prepare('SELECT * FROM reports WHERE id = ? AND user_id = ?').get(req.params.id, userId);
  if (!row) return res.status(404).json({ error: 'not found' });
  
  // Map database field names to frontend field names for compatibility
  const mappedReport = {
    ...row,
    created_at: new Date((row as any).created_at).toISOString(), // convert timestamp to ISO string
    upload_date: (row as any).created_at, // keep original timestamp for compatibility
  };
  
  res.json(mappedReport);
});

// Update report (PATCH)
const reportUpdateSchema = z.object({
  ai_summary: z.string().optional(),
  parsed: z.number().or(z.boolean()).optional(), // parsed column now exists
});

router.patch('/api/reports/:id', (req: Request, res: Response) => {
  const parsed = reportUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  
  const userId = (req as any).user?.id || (req as any).userId;
  const reportId = req.params.id;
  
  // Check if report exists and belongs to user
  const existingReport = db.prepare('SELECT * FROM reports WHERE id = ? AND user_id = ?').get(reportId, userId);
  if (!existingReport) return res.status(404).json({ error: 'report not found' });
  
  const updates = parsed.data;
  const updateFields: string[] = [];
  const updateValues: any[] = [];
  
  if (updates.ai_summary !== undefined) {
    updateFields.push('ai_summary = ?');
    updateValues.push(updates.ai_summary);
  }
  
  if (updates.parsed !== undefined) {
    updateFields.push('parsed = ?');
    updateValues.push(typeof updates.parsed === 'boolean' ? (updates.parsed ? 1 : 0) : updates.parsed);
  }
  
  if (updateFields.length === 0) {
    return res.status(400).json({ error: 'no valid fields to update' });
  }
  
  updateValues.push(reportId);
  updateValues.push(userId);
  
  const sql = `UPDATE reports SET ${updateFields.join(', ')} WHERE id = ? AND user_id = ?`;
  const info = db.prepare(sql).run(...updateValues);
  
  if (info.changes === 0) {
    return res.status(404).json({ error: 'report not found' });
  }
  
  // Return updated report
  const updatedReport = db.prepare('SELECT * FROM reports WHERE id = ? AND user_id = ?').get(reportId, userId);
  res.json(updatedReport);
});

// Parse report endpoint (placeholder for OCR/AI integration)
router.post('/api/reports/:id/parse', (req: Request, res: Response) => {
  const userId = (req as any).user?.id || (req as any).userId;
  const reportId = req.params.id;
  
  // Check if report exists and belongs to user
  const report = db.prepare('SELECT * FROM reports WHERE id = ? AND user_id = ?').get(reportId, userId) as any;
  if (!report) return res.status(404).json({ error: 'report not found' });
  
  // TODO: Implement actual OCR and AI parsing logic
  // For now, return placeholder data
  const placeholderHealthData = [
    {
      id: randomUUID(),
      user_id: userId,
  profile_id: 'default-profile',
      type: 'GLUCOSE',
      category: 'HEALTH_PARAMS',
      value: '120',
      quantity: null,
      unit: 'mg/dL',
  // Use ms epoch (was seconds previously)
  timestamp: Date.now(),
      notes: 'Extracted from report',
      report_id: reportId,
    }
  ];
  
  // Note: Database doesn't have 'parsed' column, so we skip that update
  
  // In a real implementation, save the health data entries to the database
  for (const healthData of placeholderHealthData) {
    db.prepare(`
  INSERT INTO health_data (id, user_id, profile_id, type, category, value, quantity, unit, timestamp, notes, report_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      healthData.id,
      healthData.user_id,
  healthData.profile_id,
      healthData.type,
      healthData.category,
      healthData.value,
      healthData.quantity,
      healthData.unit,
      healthData.timestamp,
      healthData.notes,
      healthData.report_id
    );
  }
  
  logger.info('Report parsed successfully', { reportId, healthDataCount: placeholderHealthData.length });
  
  res.json({
    success: true,
    health_data: placeholderHealthData,
    message: 'Report parsed successfully'
  });
});

// File upload endpoint for reports
router.post('/api/reports/upload', upload.single('file'), (req: Request, res: Response) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const userId = (req as any).user?.id || (req as any).userId;
    const reportId = randomUUID();
  const { profile_id, source, ai_summary } = req.body;
    
  // Get file information (store relative path / filename only)
  const storedFileName = path.basename(req.file.filename);
  const fileType = req.file.mimetype;
  const originalName = req.file.originalname;
  const timestamp = Date.now();
    
  // profile_id is required by database, use default if not provided
  const profileId = profile_id || 'default-profile';
    
    // Insert report record into database
    db.prepare(`INSERT INTO reports 
      (id, user_id, profile_id, file_path, file_type, source, ai_summary, created_at, parsed, original_file_name) 
      VALUES (?,?,?,?,?,?,?,?,?,?)`)
      .run(reportId, userId, profileId, storedFileName, fileType, source || 'upload', ai_summary || null, timestamp, 0, originalName);
    
    logger.info('File uploaded successfully', { 
      reportId,
      userId,
      originalName,
      fileType,
      storedFileName,
      diskLocation: path.join(reportsDir, storedFileName)
    });
    
    res.status(201).json({
      id: reportId,
      user_id: userId,
      profile_id: profileId,
      file_path: storedFileName,
      file_type: fileType,
      original_name: originalName,
      source: source || 'upload',
      ai_summary: ai_summary || null,
      created_at: new Date(timestamp).toISOString(),
      parsed: 0,
      message: 'File uploaded successfully'
    });
  } catch (error) {
    logger.error('File upload error', { error });
    res.status(500).json({ error: 'Failed to upload file' });
  }
});

// Serve uploaded files
router.get('/api/reports/files/:filename', (req: Request, res: Response) => {
  try {
    const filename = path.basename(req.params.filename); // sanitize
    const filePath = path.join(reportsDir, filename);

    if (!fs.existsSync(filePath)) {
      return res.status(404).json({ error: 'File not found' });
    }

    res.setHeader('Cache-Control', 'public, max-age=604800, immutable');
    res.sendFile(filePath);
  } catch (error) {
    logger.error('File serve error', { error });
    res.status(500).json({ error: 'Failed to serve file' });
  }
});

// Reminders CRUD
const reminderSchema = z.object({
  title: z.string(),
  time: z.string(),
  message: z.string().optional(),
  repeat: z.string().optional(),
});

router.post('/api/reminders', (req: Request, res: Response) => {
  const p = reminderSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: p.error.flatten() });
  const userId = (req as any).userId;
  const id = randomUUID();
  const { title, time, message, repeat } = p.data;
  db.prepare('INSERT INTO reminders (id, user_id, title, time, message, repeat) VALUES (?,?,?,?,?,?)')
    .run(id, userId, title, time, message || null, repeat || null);
  res.status(201).json({ id, ...p.data });
});

router.get('/api/reminders', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const rows = db.prepare('SELECT * FROM reminders WHERE user_id = ?').all(userId);
  res.json(rows);
});

router.delete('/api/reminders/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const info = db.prepare('DELETE FROM reminders WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Group members (basic add/list/remove)
const groupMemberSchema = z.object({
  group_id: z.string(),
  user_id: z.string(),
  relationship: z.string().optional(),
});

router.post('/api/group-members', (req: Request, res: Response) => {
  const p = groupMemberSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: p.error.flatten() });
  const id = randomUUID();
  const { group_id, user_id, relationship } = p.data;
  // NOTE: Authorization model for groups is not enforced here.
  db.prepare('INSERT INTO group_members (id, group_id, user_id, relationship) VALUES (?,?,?,?)')
    .run(id, group_id, user_id, relationship || null);
  res.status(201).json({ id, ...p.data });
});

router.get('/api/group-members', (req: Request, res: Response) => {
  const groupId = req.query.group_id as string | undefined;
  let rows;
  if (groupId) rows = db.prepare('SELECT * FROM group_members WHERE group_id = ?').all(groupId);
  else rows = db.prepare('SELECT * FROM group_members').all();
  res.json(rows);
});

router.delete('/api/group-members/:id', (req: Request, res: Response) => {
  const info = db.prepare('DELETE FROM group_members WHERE id = ?').run(req.params.id);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Parameter targets (user-defined reference ranges)
const paramTargetSchema = z.object({
  param_code: z.string(),
  target_min: z.number().nullable().optional(),
  target_max: z.number().nullable().optional(),
  preferred_unit: z.string().optional(),

  description: z.string().optional(),
});

router.put('/api/param-targets/:param', (req: Request, res: Response) => {
  const parsed = paramTargetSchema.safeParse({ ...req.body, param_code: req.params.param });
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const { param_code, target_min, target_max, preferred_unit, description } = parsed.data;
  db.prepare('INSERT INTO param_targets (param_code, target_min, target_max, preferred_unit, description) VALUES (?,?,?,?,?) ON CONFLICT(param_code) DO UPDATE SET target_min=excluded.target_min, target_max=excluded.target_max, preferred_unit=excluded.preferred_unit, description=excluded.description')
    .run(param_code, target_min ?? null, target_max ?? null, preferred_unit ?? null, description ?? null);
  res.status(200).json({ param_code, target_min, target_max, preferred_unit, description });
});

router.get('/api/param-targets', (_req: Request, res: Response) => {
  const rows = db.prepare('SELECT * FROM param_targets').all();
  res.json(rows);
});

// Vector similarity endpoint: given free-form message returns top matching param targets
router.post('/api/param-targets/match', (req: Request, res: Response) => {
  const { message, top } = req.body || {};
  if (!message || typeof message !== 'string') return res.status(400).json({ error: 'message required' });
  const limit = Math.min(Math.max(Number(top) || 5, 1), 20);
  const matches = matchParamTargets(message, limit);
  res.json({ message, matches });
});

router.get('/api/messages', (req: Request, res: Response) => {
  const userId = req.user?.id;
  if (!userId) return res.status(401).json({ error: 'Unauthorized' });
  const profileIdFilter = req.query.profile_id as string | undefined;
  const limit = Math.min(Number(req.query.limit || 50), 200);
  const before = req.query.before ? Number(req.query.before) : undefined; // cursor (created_at)

  // Include:
  //  - User's own messages (sender_id = userId)
  //  - Assistant/system messages in profiles the user is a member of
  // We derive membership via profile_members; fallback include default 'me-profile'
  let base = `SELECT m.id, m.profile_id, m.sender_id, m.role, m.content, m.created_at, m.processed, m.stored_record_id, m.interpretation_json
              FROM messages m
              LEFT JOIN profile_members pm ON pm.profile_id = m.profile_id AND pm.user_id = ?
              WHERE (m.sender_id = ? OR (m.role != 'user' AND pm.user_id IS NOT NULL))`;
  const params: any[] = [userId, userId];
  if (profileIdFilter) { base += ' AND m.profile_id = ?'; params.push(profileIdFilter); }
  if (before) { base += ' AND m.created_at < ?'; params.push(before); }
  base += ' ORDER BY m.created_at DESC LIMIT ?'; params.push(limit);
  const rows = db.prepare(base).all(...params) as any[];
  const nextCursor = rows.length === limit ? rows[rows.length - 1].created_at : null;
  res.json({ items: rows, paging: { limit, nextCursor } });
});

// Reprocess failed messages
router.post('/api/messages/reprocess-failed', async (req: Request, res: Response) => {
  const userId = (req as any).userId;
  
  // Find messages that failed processing (processed=1 but stored_record_id is null)
  const failedMessages = db.prepare(`
    SELECT * FROM messages 
    WHERE user_id = ? AND processed = 1 AND stored_record_id IS NULL 
    ORDER BY created_at DESC LIMIT 10
  `).all(userId);
  
  const results = [];
  
  for (const msg of failedMessages as DbMessage[]) {
    try {
      logger.info('Reprocessing failed message', { messageId: msg.id, content: msg.content });
      
      const interpretation = await interpretMessage(msg.content);
      
      if (interpretation.parsed && interpretation.entry) {
        try {
          const stored = persistAiEntry(interpretation.entry, userId, (msg as any).profile_id);
          db.prepare('UPDATE messages SET interpretation_json = ?, stored_record_id = ? WHERE id = ?')
            .run(JSON.stringify(interpretation), stored.id, msg.id);
          
          results.push({
            messageId: msg.id,
            content: msg.content,
            status: 'success',
            storedId: stored.id,
            storedType: stored.type || stored.name
          });
          
          logger.info('Reprocessed message successfully', { messageId: msg.id, storedId: stored.id });
        } catch (persistError: any) {
          db.prepare('UPDATE messages SET interpretation_json = ? WHERE id = ?')
            .run(JSON.stringify({ error: persistError.message, interpretation }), msg.id);
          
          results.push({
            messageId: msg.id,
            content: msg.content,
            status: 'persist_failed',
            error: persistError.message
          });
        }
      } else {
        db.prepare('UPDATE messages SET interpretation_json = ? WHERE id = ?')
          .run(JSON.stringify(interpretation), msg.id);
        
        results.push({
          messageId: msg.id,
          content: msg.content,
          status: 'not_parsed',
          interpretation
        });
      }
    } catch (error: any) {
      results.push({
        messageId: msg.id,
        content: msg.content,
        status: 'error',
        error: error.message
      });
      
      logger.error('Failed to reprocess message', { messageId: msg.id, error: error.message });
    }
  }
  
  res.json({
    processed: results.length,
    results
  });
});

// --- Generic (read-only) data browsing endpoints for UI Data page ---
// NOTE: These are development convenience endpoints; consider securing or removing in production.
const BROWSABLE_TABLES = [
  'activities',
  'health_data',
  'medications',
  'medication_schedules',
  'medication_schedule_times',
  'medication_intake_logs',
  'messages',
  'param_targets',
  'reminders',
  'reports'
];

router.get('/api/admin/tables', (_req: Request, res: Response) => {
  res.json({ tables: BROWSABLE_TABLES });
});

router.get('/api/admin/table/:name', (req: Request, res: Response) => {
  const name = req.params.name;
  if (!BROWSABLE_TABLES.includes(name)) return res.status(400).json({ error: 'table not allowed' });
  const limit = Math.min(Math.max(Number(req.query.limit) || 20, 1), 100);
  const page = Math.max(Number(req.query.page) || 1, 1);
  const offset = (page - 1) * limit;
  let orderCol = 'rowid';
  if (name === 'health_data') orderCol = 'timestamp';
  else if (name === 'messages') orderCol = 'created_at';
  else if (name === 'reports') orderCol = 'upload_date';
  const totalRow = db.prepare(`SELECT COUNT(*) as c FROM ${name}`).get() as any;
  const total = totalRow?.c || 0;
  const rows = db.prepare(`SELECT * FROM ${name} ORDER BY ${orderCol} DESC LIMIT ? OFFSET ?`).all(limit, offset) as any[];
  const columns = rows.length ? Object.keys(rows[0]) : (db.prepare(`PRAGMA table_info(${name})`).all() as any[]).map(r => r?.name).filter(Boolean);
  res.json({ table: name, columns, items: rows, paging: { page, limit, count: rows.length, total } });
});

export default router;
