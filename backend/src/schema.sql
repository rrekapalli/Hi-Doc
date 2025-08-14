-- users
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT,
  email TEXT UNIQUE,
  photo_url TEXT
);

-- group_members
CREATE TABLE IF NOT EXISTS group_members (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  relationship TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- health_data
CREATE TABLE IF NOT EXISTS health_data (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  type TEXT NOT NULL,
  category TEXT DEFAULT 'HEALTH_PARAMS',
  value TEXT,
  quantity TEXT,
  unit TEXT,
  timestamp INTEGER NOT NULL,
  notes TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- medications
CREATE TABLE IF NOT EXISTS medications (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  dosage TEXT,
  schedule TEXT,
  duration_days INTEGER,
  is_forever INTEGER DEFAULT 0,
  start_date INTEGER,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- reports
CREATE TABLE IF NOT EXISTS reports (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  type TEXT,
  ai_summary TEXT,
  upload_date INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- reminders
CREATE TABLE IF NOT EXISTS reminders (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL,
  time TEXT NOT NULL,
  message TEXT,
  repeat TEXT,
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);


CREATE INDEX IF NOT EXISTS idx_health_data_user_ts ON health_data(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_health_data_category ON health_data(category);
CREATE INDEX IF NOT EXISTS idx_medications_user ON medications(user_id);
CREATE INDEX IF NOT EXISTS idx_reports_user ON reports(user_id);
CREATE INDEX IF NOT EXISTS idx_reminders_user ON reminders(user_id);

-- Raw user messages captured before AI interpretation
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'user', -- 'user', 'assistant', 'system'
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  interpretation_json TEXT,
  processed INTEGER DEFAULT 0, -- 0=pending,1=attempted/complete
  stored_record_id TEXT, -- links to health_data.id (or future measurements table)
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_messages_user_time ON messages(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_role ON messages(role);

-- Parsed parameters extracted from messages
CREATE TABLE IF NOT EXISTS parsed_parameters (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  category TEXT NOT NULL,
  parameter TEXT NOT NULL,
  value TEXT NOT NULL,
  unit TEXT,
  datetime TEXT,
  raw_json TEXT,
  FOREIGN KEY(message_id) REFERENCES messages(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_parsed_params_message ON parsed_parameters(message_id);
CREATE INDEX IF NOT EXISTS idx_parsed_params_category ON parsed_parameters(category);

-- Global parameter targets / reference ranges (application-level)
CREATE TABLE IF NOT EXISTS param_targets (
  param_code TEXT PRIMARY KEY,
  target_min REAL,
  target_max REAL,
  preferred_unit TEXT,
  description TEXT,
  notes TEXT,
  organ_system TEXT
);
