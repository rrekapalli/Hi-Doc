import { Router, Request as ExpressRequest, Response, NextFunction } from 'express';
import { db } from './db.js';
import { randomUUID } from 'crypto';
import { z } from 'zod';
import { signToken, verifyToken } from './jwtUtil.js';
import { interpretMessage, aiProviderStatus, AiInterpretation, getHealthDataEntryPrompt, getHealthDataTrendPrompt, clearPromptCache } from './ai.js';

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
interface DbMessage {
  id: string;
  conversation_id: string;
  sender_id: string;
  user_id: string;
  role: 'user' | 'system' | 'assistant';
  content: string;
  created_at: number;
  processed?: number;
  interpretation_json?: string;
}

const router = Router();

// Import conversation-related functions
import {
  getConversations,
  getMessages,
  sendMessage,
  createConversation,
  markConversationAsRead,
  updateConversationTitle,
  addConversationMembers,
  removeConversationMember,
  getConversationMembers,
} from './conversations.js';

// Conversation routes
router.get('/api/conversations', async (req: Request, res: Response) => {
  try {
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const conversations = await getConversations(userId);
    res.json(conversations);
  } catch (error) {
    logger.error('Error getting conversations:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/api/conversations/:id/messages', async (req: Request, res: Response) => {
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

router.post('/api/conversations/:id/messages', async (req: Request, res: Response) => {
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
      conversation_id: id,
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

router.post('/api/conversations', async (req: Request, res: Response) => {
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

    const conversationId = await createConversation(
      title,
      type,
      uniqueMemberIds,
      userId
    );

    res.json({ id: conversationId });
  } catch (error) {
    logger.error('Error creating conversation:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/conversations/:id/read', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const userId = req.user?.id;
    if (!userId) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    await markConversationAsRead(id, userId);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error marking conversation as read:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.put('/api/conversations/:id/title', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { title } = req.body;
    if (!title) {
      return res.status(400).json({ error: 'Title is required' });
    }

    await updateConversationTitle(id, title);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error updating conversation title:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.post('/api/conversations/:id/members', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { userIds } = req.body;
    if (!userIds || !Array.isArray(userIds)) {
      return res.status(400).json({ error: 'User IDs array is required' });
    }

    await addConversationMembers(id, userIds);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error adding conversation members:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.delete('/api/conversations/:id/members/:userId', async (req: Request, res: Response) => {
  try {
    const { id, userId } = req.params;
    await removeConversationMember(id, userId);
    res.json({ success: true });
  } catch (error) {
    logger.error('Error removing conversation member:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

router.get('/api/conversations/:id/members', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const members = await getConversationMembers(id);
    res.json(members);
  } catch (error) {
    logger.error('Error getting conversation members:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Search users endpoint for creating new conversations
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

// --- Simple in-memory vector search over param_targets (bag-of-words cosine) ---
// This avoids external dependencies while enabling approximate semantic mapping of a user message
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
  const stmt = db.prepare('SELECT param_code, target_min, target_max, preferred_unit, description, notes, organ_system FROM param_targets');
  const rows = (stmt.all() as unknown) as ParamTargetRow[];
  if (!Array.isArray(rows)) {
    return [];
  }
  const msgVec = buildVector(tokenize(message));
  const scored = rows.map(r => {
    const text = [r.param_code, r.description, r.notes, r.organ_system].filter(Boolean).join(' ');
    const vec = buildVector(tokenize(text));
    return { row: r, score: cosine(msgVec, vec) };
  }).filter(s => s.score > 0).sort((a,b)=> b.score - a.score).slice(0, limit);
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
  const payload = await verifyMicrosoftIdToken(idToken);
  const email = payload.email || payload.preferred_username;
  if (!email) { logger.warn('Microsoft exchange email claim missing'); return res.status(400).json({ error: 'email claim missing' }); }
  const user: any = upsertUser(email, payload.name, (payload as any).picture);
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

// Prototype mode: Skip authentication and use a hardcoded user ID
router.use((req: Request, res: Response, next: NextFunction) => {
  // Use a fixed prototype user ID and ensure it exists
  const prototypeUserId = 'prototype-user-12345';
  const defaultEmail = 'prototype@example.com';
  
  // Check if user exists, create if not
  let user = db.prepare('SELECT * FROM users WHERE id = ?').get(prototypeUserId);
  if (!user) {
    logger.debug('Creating prototype user in middleware', { userId: prototypeUserId, email: defaultEmail });
    try {
      db.prepare('INSERT OR IGNORE INTO users (id, name, email, photo_url) VALUES (?, ?, ?, ?)').run(prototypeUserId, 'Prototype User', defaultEmail, null);
      user = db.prepare('SELECT * FROM users WHERE id = ?').get(prototypeUserId);
      logger.debug('Prototype user created in middleware', { user });
    } catch (e) {
      logger.error('Failed to create prototype user in middleware', { error: e });
    }
  }
  
  (req as any).userId = prototypeUserId;
  logger.debug('Using hardcoded prototype user', { userId: prototypeUserId, path: req.path });
  next();
});

// Simple regex-based health message parser as fallback
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
    
    db.prepare('INSERT INTO messages (id, conversation_id, sender_id, role, content, created_at, processed) VALUES (?,?,?,?,?,?,0)')
      .run(userMessageId, 'me-conversation', userId, 'user', String(message), createdAt);
    
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
      
      db.prepare('INSERT INTO messages (id, conversation_id, sender_id, role, content, created_at, processed) VALUES (?,?,?,?,?,?,1)')
        .run(aiMessageId, 'me-conversation', userId, 'assistant', aiResponse, Date.now());
      
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
  const { id, user_id, conversation_id, type, category, value, quantity, unit, timestamp, notes } = req.body || {};
  
  if (!id || !user_id || !conversation_id || !type || !timestamp) {
    return res.status(400).json({ error: 'id, user_id, conversation_id, type, and timestamp are required' });
  }
  
  try {
    // Check if quantity column exists
    const tableInfo = db.prepare('PRAGMA table_info(health_data)').all() as any[];
    const hasQuantity = tableInfo.some((col: any) => col.name === 'quantity');
    
    if (hasQuantity) {
      db.prepare(`
        INSERT INTO health_data (id, user_id, conversation_id, type, category, value, quantity, unit, timestamp, notes) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        user_id,
        conversation_id,
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
        INSERT INTO health_data (id, user_id, conversation_id, type, category, value, unit, timestamp, notes) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        id,
        user_id,
        conversation_id,
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

// AI interpret + persist (requires auth). This does not change existing provisional local insert logic on the client;
// it offers a backend mapping path so the AI output becomes a stored row.
router.post('/api/ai/interpret-store', async (req: Request, res: Response) => {
  const { message } = req.body || {};
  if (!message) { logger.warn('Interpret-store missing message'); return res.status(400).json({ error: 'message required' }); }
  const userId = (req as any).user?.id || (req as any).userId;
  logger.debug('Interpret-store userId check', { userId, hasUserId: !!userId, type: typeof userId });

  
  // Store raw message first
  const msgId = randomUUID();
  const createdAt = Date.now();
  db.prepare('INSERT INTO messages (id, conversation_id, sender_id, role, content, created_at, processed) VALUES (?,?,?,?,?,?,0)')
    .run(msgId, 'default-conversation', userId, 'user', String(message), createdAt);
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
    const stored = persistAiEntry(interpretation.entry, userId, 'default-conversation');
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
function persistAiEntry(entry: NonNullable<AiInterpretation['entry']>, userId: string, conversationId: string) {
  const id = randomUUID();
  const ts = entry.timestamp ?? Date.now();
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
      db.prepare('INSERT INTO health_data (id, user_id, conversation_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, conversationId, vt, category, value, unit, ts, null);
      return { table: 'health_data', id, type: vt, category, value, unit, timestamp: ts };
    }
    case 'param': {
      if (!entry.param || !entry.param.param_code) throw new Error('param.param_code missing');
      const p = entry.param;
      const value = p.value != null ? String(p.value) : null;
      const unit = p.unit || null;
      const notes = p.notes || null;
      logger.debug('DB insert param as health_data', { code: p.param_code, value, unit, category, ts });
      db.prepare('INSERT INTO health_data (id, user_id, conversation_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, conversationId, p.param_code, category, value, unit, ts, notes);
      return { table: 'health_data', id, type: p.param_code, category, value, unit, notes, timestamp: ts };
    }
    case 'note': {
      const noteId = id;
      const noteText = entry.note || '';
      logger.debug('DB insert note', { category, ts });
      db.prepare('INSERT INTO health_data (id, user_id, conversation_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(noteId, userId, conversationId, 'note', category, null, null, ts, noteText);
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
      logger.debug('DB insert medication', { name: m.name, dosage, schedule, duration: m.durationDays, conversationId });
      db.prepare('INSERT INTO medications (id, user_id, conversation_id, name, dosage, schedule, duration_days, is_forever, start_date) VALUES (?,?,?,?,?,?,?,?,?)')
        .run(id, userId, conversationId, m.name, dosage || null, schedule, m.durationDays ?? null, 0, ts);
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
      logger.debug('DB insert activity', { name: a.name, distance: a.distance_km, duration: a.duration_minutes, intensity: a.intensity, conversationId });
      db.prepare('INSERT INTO activities (id, user_id, conversation_id, name, duration_minutes, distance_km, intensity, calories_burned, timestamp, notes) VALUES (?,?,?,?,?,?,?,?,?,?)')
        .run(id, userId, conversationId, a.name, a.duration_minutes ?? null, a.distance_km ?? null, a.intensity ?? null, a.calories_burned ?? null, ts, a.notes ?? null);
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
});

router.post('/api/health', (req: Request, res: Response) => {
  const parsed = healthDataSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const id = randomUUID();
  const userId = (req as any).userId;
  const { type, category, value, unit, timestamp, notes } = parsed.data;
  const ts = timestamp ?? Date.now();
  const cat = category || 'HEALTH_PARAMS';
  db.prepare('INSERT INTO health_data (id, user_id, type, category, value, unit, timestamp, notes) VALUES (?,?,?,?,?,?,?,?)')
    .run(id, userId, type, cat, value || null, unit || null, ts, notes || null);
  res.status(201).json({ id, type, category: cat, value, unit, timestamp: ts, notes });
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

// Medications CRUD
const medicationSchema = z.object({
  name: z.string(),
  dosage: z.string().optional(),
  schedule: z.string().optional(),
  duration_days: z.number().int().optional(),
  is_forever: z.boolean().optional(),
  start_date: z.number().int().optional(),
});

router.post('/api/medications', (req: Request, res: Response) => {
  const parsed = medicationSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  const userId = (req as any).userId;
  const id = randomUUID();
  const { name, dosage, schedule, duration_days, is_forever, start_date } = parsed.data;
  db.prepare('INSERT INTO medications (id, user_id, name, dosage, schedule, duration_days, is_forever, start_date) VALUES (?,?,?,?,?,?,?,?)')
    .run(id, userId, name, dosage || null, schedule || null, duration_days ?? null, is_forever ? 1 : 0, start_date ?? null);
  res.status(201).json({ id, ...parsed.data });
});

router.get('/api/medications', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const activeOnly = req.query.active === 'true';
  const rows = db.prepare('SELECT * FROM medications WHERE user_id = ?').all(userId)
    .filter((r: any) => !activeOnly || r.is_forever === 1 || (r.duration_days && r.start_date && (Date.now() - r.start_date) / 86400000 <= r.duration_days));
  res.json(rows);
});

router.delete('/api/medications/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const info = db.prepare('DELETE FROM medications WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Reports CRUD
const reportSchema = z.object({
  id: z.string().optional(),
  user_id: z.string().optional(),
  conversation_id: z.string().optional(),
  file_path: z.string(),
  file_type: z.string().optional(),
  source: z.string().optional(),
  ai_summary: z.string().optional(),
  created_at: z.number().int().optional(),
  parsed: z.number().int().min(0).max(1).optional(),
});

router.post('/api/reports', (req: Request, res: Response) => {
  const p = reportSchema.safeParse(req.body);
  if (!p.success) return res.status(400).json({ error: p.error.flatten() });
  const userId = (req as any).userId;
  const reportId = p.data.id || randomUUID();
  const { conversation_id, file_path, file_type, source, ai_summary, created_at, parsed } = p.data;
  const ts = created_at ?? Date.now();
  
  db.prepare(`INSERT INTO reports 
    (id, user_id, conversation_id, file_path, file_type, source, ai_summary, created_at, parsed) 
    VALUES (?,?,?,?,?,?,?,?,?)`)
    .run(reportId, userId, conversation_id || null, file_path, file_type || 'unknown', 
         source || 'upload', ai_summary || null, ts, parsed || 0);
  
  res.status(201).json({ 
    id: reportId, 
    user_id: userId,
    conversation_id: conversation_id || null,
    file_path, 
    file_type: file_type || 'unknown',
    source: source || 'upload',
    ai_summary: ai_summary || null,
    created_at: ts,
    parsed: parsed || 0
  });
});

router.get('/api/reports', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const file_type = req.query.file_type as string | undefined;
  let sql = 'SELECT * FROM reports WHERE user_id = ?';
  const params: any[] = [userId];
  if (file_type) { sql += ' AND file_type = ?'; params.push(file_type); }
  sql += ' ORDER BY created_at DESC';
  const rows = db.prepare(sql).all(...params);
  res.json(rows);
});

router.delete('/api/reports/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const info = db.prepare('DELETE FROM reports WHERE id = ? AND user_id = ?').run(req.params.id, userId);
  if (info.changes === 0) return res.status(404).json({ error: 'not found' });
  res.status(204).end();
});

// Get single report
router.get('/api/reports/:id', (req: Request, res: Response) => {
  const userId = (req as any).userId;
  const row = db.prepare('SELECT * FROM reports WHERE id = ? AND user_id = ?').get(req.params.id, userId);
  if (!row) return res.status(404).json({ error: 'not found' });
  res.json(row);
});

// Update report (PATCH)
const reportUpdateSchema = z.object({
  ai_summary: z.string().optional(),
  parsed: z.number().int().min(0).max(1).optional(),
});

router.patch('/api/reports/:id', (req: Request, res: Response) => {
  const parsed = reportUpdateSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() });
  
  const userId = (req as any).userId;
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
    updateValues.push(updates.parsed);
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
  const userId = (req as any).userId;
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
      conversation_id: 'default-conversation',
      type: 'GLUCOSE',
      category: 'HEALTH_PARAMS',
      value: '120',
      quantity: null,
      unit: 'mg/dL',
      timestamp: Math.floor(Date.now() / 1000),
      notes: 'Extracted from report',
      report_id: reportId,
    }
  ];
  
  // Mark report as parsed
  db.prepare('UPDATE reports SET parsed = 1 WHERE id = ? AND user_id = ?').run(reportId, userId);
  
  // In a real implementation, save the health data entries to the database
  for (const healthData of placeholderHealthData) {
    db.prepare(`
      INSERT INTO health_data (id, user_id, conversation_id, type, category, value, quantity, unit, timestamp, notes, report_id)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      healthData.id,
      healthData.user_id,
      healthData.conversation_id,
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
  if (!userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  
  const conversationId = req.query.conversation_id;
  const limit = Math.min(Number(req.query.limit || 50), 500);
  
  let query = 'SELECT * FROM messages WHERE sender_id = ?';
  const params: any[] = [userId];
  
  if (conversationId) {
    query += ' AND conversation_id = ?';
    params.push(conversationId);
  }
  
  query += ' ORDER BY created_at DESC LIMIT ?';
  params.push(limit);
  
  const rows = db.prepare(query).all(...params);
  res.json({ items: rows });
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
          const stored = persistAiEntry(interpretation.entry, userId, msg.conversation_id);
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
  'activities', 'health_data', 'medications', 'messages', 'param_targets', 'reminders', 'reports'
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
