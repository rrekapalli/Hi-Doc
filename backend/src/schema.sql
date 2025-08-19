-- Enable foreign key support
PRAGMA foreign_keys = ON;

-- Create users table if not exists
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT,
  email TEXT UNIQUE,
  photo_url TEXT
);

-- Create conversations table
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT,
  type TEXT NOT NULL DEFAULT 'direct',
  is_default INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Create conversation_members table
CREATE TABLE IF NOT EXISTS conversation_members (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  is_admin INTEGER DEFAULT 0,
  joined_at INTEGER NOT NULL,
  last_read_at INTEGER NOT NULL,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Create messages table with conversation support
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user',
  content TEXT NOT NULL,
  content_type TEXT DEFAULT 'text',
  created_at INTEGER NOT NULL,
  interpretation_json TEXT,
  processed INTEGER DEFAULT 0,
  stored_record_id TEXT,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY(sender_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Create all other tables with conversation_id (except param_targets)
CREATE TABLE IF NOT EXISTS health_data (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  type TEXT NOT NULL,
  category TEXT DEFAULT 'HEALTH_PARAMS',
  value TEXT,
  quantity TEXT,
  unit TEXT,
  timestamp INTEGER NOT NULL,
  notes TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  name TEXT NOT NULL,
  dosage TEXT,
  schedule TEXT,
  duration_days INTEGER,
  is_forever INTEGER DEFAULT 0,
  start_date INTEGER,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  type TEXT,
  ai_summary TEXT,
  upload_date INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS reminders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  medication_id TEXT,
  title TEXT NOT NULL,
  time TEXT NOT NULL,
  message TEXT,
  repeat TEXT,
  days TEXT,
  active INTEGER DEFAULT 1,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
  FOREIGN KEY(medication_id) REFERENCES medications(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS activities (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  conversation_id TEXT NOT NULL,
  name TEXT NOT NULL,
  duration_minutes INTEGER,
  distance_km REAL,
  intensity TEXT,
  calories_burned REAL,
  timestamp INTEGER NOT NULL,
  notes TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- Create param_targets table (no conversation_id needed as requested)
CREATE TABLE IF NOT EXISTS param_targets (
  param_code TEXT PRIMARY KEY,
  target_min REAL,
  target_max REAL,
  preferred_unit TEXT,
  description TEXT,
  notes TEXT,
  organ_system TEXT
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_health_data_user_ts ON health_data(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_health_data_category ON health_data(category);
CREATE INDEX IF NOT EXISTS idx_health_data_conversation ON health_data(conversation_id);
CREATE INDEX IF NOT EXISTS idx_medications_user ON medications(user_id);
CREATE INDEX IF NOT EXISTS idx_medications_conversation ON medications(conversation_id);
CREATE INDEX IF NOT EXISTS idx_reports_user ON reports(user_id);
CREATE INDEX IF NOT EXISTS idx_reports_conversation ON reports(conversation_id);
CREATE INDEX IF NOT EXISTS idx_reminders_user ON reminders(user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_conversation ON reminders(conversation_id);
CREATE INDEX IF NOT EXISTS idx_activities_user ON activities(user_id);
CREATE INDEX IF NOT EXISTS idx_activities_conversation ON activities(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_user ON conversation_members(user_id);
CREATE INDEX IF NOT EXISTS idx_conversation_members_convo ON conversation_members(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_time ON messages(conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);

-- Insert seed data
-- Create default user for development
INSERT OR IGNORE INTO users (id, name, email) 
VALUES ('prototype-user-12345', 'Dev User', 'dev@example.com');

-- Create default conversation
INSERT OR IGNORE INTO conversations (
  id,
  title,
  type,
  is_default,
  created_at,
  updated_at
) VALUES (
  'default-conversation',
  'Me',
  'direct',
  1,
  strftime('%s', 'now') * 1000,
  strftime('%s', 'now') * 1000
);

-- Add dev user to default conversation
INSERT OR IGNORE INTO conversation_members (
  id,
  conversation_id,
  user_id,
  is_admin,
  joined_at,
  last_read_at
) VALUES (
  'member_default_prototype-user-12345',
  'default-conversation',
  'prototype-user-12345',
  1,
  strftime('%s', 'now') * 1000,
  strftime('%s', 'now') * 1000
);
