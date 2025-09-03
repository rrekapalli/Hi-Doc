You are updating the complete Medications module in this Flutter health tracker app.

## GOAL
Build end-to-end medications management with:
- Normalized schema (medications, medication_schedules, medication_schedule_times)
- Natural language entry - already impleneted (parse free text like “dolo 650 twice daily, morning & night for 5 days”)
- CRUD UI (list, view, add, edit, delete)
- Multi-schedule, multi-time support (different dosage at different times)
- Optional reminder notifications per schedule time
- Optional adherence logs (taken/missed)

--------------------------------------------
## DATABASE (SQLite)

-- 1) Medications: the "what" (drug per user/profile)
CREATE TABLE IF NOT EXISTS medications (
  id TEXT PRIMARY KEY,                 -- UUID
  user_id TEXT NOT NULL,
  profile_id TEXT NOT NULL,
  name TEXT NOT NULL,                  -- e.g., "Atorvastatin", "Dolo"
  notes TEXT,                          -- optional generic instructions
  medication_url TEXT,                 -- URL about the medication from any trusted source
  created_at INTEGER NOT NULL,         -- epoch ms
  updated_at INTEGER NOT NULL,         -- epoch ms
  FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY(profile_id) REFERENCES profiles(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_medications_user_profile ON medications(user_id, profile_id);
CREATE INDEX IF NOT EXISTS idx_medications_name ON medications(name);

-- 2) Medication Schedules: the "when/how" (recurrence window)
CREATE TABLE IF NOT EXISTS medication_schedules (
  id TEXT PRIMARY KEY,                 -- UUID
  medication_id TEXT NOT NULL,         -- FK -> medications.id
  schedule TEXT NOT NULL,              -- human-readable, e.g., "daily", "every 8 hours", "weekends"
  frequency_per_day INTEGER,           -- optional (e.g., 2)
  is_forever INTEGER DEFAULT 0,        -- 1=indefinite, 0=bounded
  start_date INTEGER,                  -- epoch ms; nullable
  end_date INTEGER,                    -- epoch ms; nullable if forever
  days_of_week TEXT,                   -- optional CSV "MON,TUE,..." or "0-6"
  timezone TEXT,                       -- IANA tz (e.g., "Asia/Kolkata")
  reminder_enabled INTEGER DEFAULT 1,  -- 1=on, 0=off
  FOREIGN KEY(medication_id) REFERENCES medications(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_schedules_medication ON medication_schedules(medication_id);
CREATE INDEX IF NOT EXISTS idx_schedules_active_window ON medication_schedules(start_date, end_date);

-- 3) Medication Schedule Times: the exact dose times & dosage per schedule
CREATE TABLE IF NOT EXISTS medication_schedule_times (
  id TEXT PRIMARY KEY,                 -- UUID
  schedule_id TEXT NOT NULL,           -- FK -> medication_schedules.id
  time_local TEXT NOT NULL,            -- "HH:MM" 24h, in schedule timezone
  dosage TEXT,                         -- free text (e.g., "1 tab", "10 mL")
  dose_amount REAL,                    -- numeric (optional)
  dose_unit TEXT,                      -- "mg","mcg","mL","tabs","IU"
  instructions TEXT,                   -- "before breakfast", "with food", etc.
  prn INTEGER DEFAULT 0,               -- 1=as needed, 0=fixed time
  sort_order INTEGER,                  -- for UI ordering
  next_trigger_ts INTEGER,             -- cached next alarm epoch ms (optional)
  FOREIGN KEY(schedule_id) REFERENCES medication_schedules(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_times_schedule ON medication_schedule_times(schedule_id);
CREATE INDEX IF NOT EXISTS idx_times_trigger ON medication_schedule_times(next_trigger_ts);

-- (Optional) Intake logs for adherence
CREATE TABLE IF NOT EXISTS medication_intake_logs (
  id TEXT PRIMARY KEY,
  schedule_time_id TEXT NOT NULL,
  taken_ts INTEGER NOT NULL,           -- epoch ms
  status TEXT NOT NULL,                -- "taken","missed","skipped","snoozed"
  actual_dose_amount REAL,
  actual_dose_unit TEXT,
  notes TEXT,
  FOREIGN KEY(schedule_time_id) REFERENCES medication_schedule_times(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_intake_logs_time ON medication_intake_logs(taken_ts);

--------------------------------------------
## FEATURE SCOPE

A) INPUT (Natural Language → Structured)
- Accept messages (from messages screen - already impleneted) like:
  • "Dolo 650 twice daily, morning before breakfast and night before dinner for 5 days"
  • "Atorvastatin 10 mg nightly, lifelong"
  • "Levothyroxine 75 mcg daily at 6:30 AM, before breakfast"
- Parse into:
  • medication: { name, notes? }
  • schedule: { schedule text, frequency_per_day?, is_forever, start_date, end_date?, days_of_week?, timezone }
  • times[]: [{ time_local, dosage, dose_amount?, dose_unit?, instructions?, prn? }]
- Compute end_date = start_date + duration_days*86400000 when finite.
- Generate UUIDs for each table row; set timestamps (created_at/updated_at).

B) UI/UX
1. Medications List (medication_list.png)
   - Search bar; filter by active/archived; sort by name or recently updated.
   - Item shows: name, next dose time(s) today (if any), active schedules count.
   - FAB: "Add medication"

2. Medication Detail
   - Header: name, notes.
   - Sections:
     • Schedules (card per schedule: schedule text, window (start→end or Forever), days_of_week, timezone, reminder toggle)
     • Times inside each schedule (list of dose rows: time_local, dosage, instructions, PRN badge)
   - Actions: Edit/Delete medication; Add schedule; Add time; Archive medication.

3. Add/Edit Medication Flow (medication_schedule.png)
   Step 1: Medication basics (name, notes)
   Step 2: Schedule window (daily/every N hours/custom, is_forever, start_date/end_date, days_of_week, timezone)
   Step 3: Dose times (one or many; per-time dosage & instructions; PRN option)
   Step 4: Reminders (toggle; propose defaults; confirm times)
   Save → persist rows across 3 tables.

4. Reminders/Notifications
   - If reminder_enabled = 1:
     • For each schedule_time row, compute next_trigger_ts using timezone + start/end + days_of_week + time_local.
     • Schedule local notifications at those times (Android/iOS).
     • On firing, notification payload includes medication_id, schedule_id, schedule_time_id.

5. Intake Logging
   - From notification or detail screen, user can mark dose as taken/skipped/snoozed.
   - Create `medication_intake_logs` rows accordingly.

C) SERVICES / LAYERS
- Data Models (freezed/json_serializable or manual):
  • Medication
  • MedicationSchedule
  • MedicationScheduleTime
  • (Optional) MedicationIntakeLog
- Repository methods:
  • MedicationsRepo:
    - createMedication(med: Medication)
    - updateMedication(med: Medication)
    - deleteMedication(id)
    - getMedications(userId, profileId)
    - getMedicationById(id)
  • MedSchedulesRepo:
    - createSchedule(schedule)
    - updateSchedule(schedule)
    - deleteSchedule(id)
    - getSchedules(medicationId)
  • MedScheduleTimesRepo:
    - createTime(time)
    - updateTime(time)
    - deleteTime(id)
    - getTimes(scheduleId)
  • (Optional) IntakeLogsRepo:
    - logIntake(scheduleTimeId, status, takenTs, {dose_amount, dose_unit, notes})
    - listLogsByMedication(medicationId, fromTs?, toTs?)
- ReminderService:
  • computeNextTrigger(schedule, timeRow, now, tz)
  • scheduleLocalNotification(scheduleTimeId, nextTriggerTs)
  • cancelNotificationsForMedication(medicationId)
  • rescheduleAllForProfile(profileId)

D) NATURAL LANGUAGE PARSER (Deterministic-first, LLM-assisted optional - already impleneted in 'messages' screen with prompt './assets/prompts/medication_data_entry_prompt.txt' - update if required)
- Recognize:
  • Medication name (first drug-like token sequence)
  • Dosage tokens: "<number> mg|mcg|mL|IU|tabs"
  • Frequency: "once|twice|thrice daily", "every <N> hours", "nightly", "morning & night"
  • Specific times: "at 6:30 am", "8 pm"
  • Relative times to meals: "before breakfast", "after dinner"
  • Duration: "for 5 days|3 weeks|2 months"; “forever|lifelong”
  • Start date: "starting tomorrow|from <date>"
  • Days of week: "Mon-Fri", "weekends"
  • PRN: "as needed", “if pain”
- Output structure (example):
  {
    "medication": {"name":"Dolo","notes":null},
    "schedule": {
      "schedule":"daily",
      "frequency_per_day":2,
      "is_forever":0,
      "start_date": 1733011200000,
      "end_date": 1733443200000,
      "days_of_week": null,
      "timezone":"Asia/Kolkata",
      "reminder_enabled":1
    },
    "times":[
      {"time_local":"08:00","dosage":"1 tab (650 mg)","dose_amount":650,"dose_unit":"mg","instructions":"before breakfast","prn":0,"sort_order":1},
      {"time_local":"20:00","dosage":"1 tab (650 mg)","dose_amount":650,"dose_unit":"mg","instructions":"before dinner","prn":0,"sort_order":2}
    ]
  }

E) VALIDATION & RULES
- Name required; at least one schedule and one time per schedule unless PRN-only schedule (then time_local may be omitted if PRN=1).
- If is_forever=1 → end_date must be NULL.
- If duration provided → compute end_date from start_date.
- Enforce timezone default (from profile/app settings).
- Sort times by sort_order/time_local for display.
- On edit:
  • Update updated_at.
  • Recompute next_trigger_ts and reschedule notifications affected.

F) MIGRATION (if previous single-table existed)
- For each old record:
  • Insert into `medications` (omit dosage).
  • Make one `medication_schedules` row (map old schedule/start/duration/is_forever).
  • Create one or more `medication_schedule_times` from prior dosage & implied times.
- Preserve reminder settings; re-schedule notifications.

G) TEST CASES / ACCEPTANCE
- Create:
  • Daily 2x schedule with different morning/night dosages.
  • Every 8 hours schedule for 7 days.
  • PRN schedule without fixed times.
- Edit:
  • Change time from 08:00 to 07:30 → notification rescheduled.
  • Toggle reminder_enabled → notifications cancel/resume.
- Delete:
  • Deleting a medication cascades to schedules, times, notifications.
- NLP:
  • “Atorvastatin 10 mg at night, lifelong” parses to 1 schedule, 1 time, is_forever=1.
  • “Paracetamol 500 mg every 6 hours for 5 days starting tomorrow” → q6h, duration 5d, 4 times/day (derive evenly spaced times if requested).
- UI:
  • List shows next dose times today correctly (respect timezone & days_of_week).
  • Detail page shows schedules and times with edit/delete.

H) DELIVERABLES
- Dart models + SQLite DAOs/Repositories.
- State management (Provider/Riverpod/BLoC).
- Screens:
  • MedicationsListScreen
  • MedicationDetailScreen
  • MedicationEditor (wizard: medication → schedule → times → reminders)
- Services:
  • NaturalLanguageMedicationParser (deterministic rules; pluggable LLM)
  • ReminderService (platform notifications)
- Unit tests for:
  • Parser scenarios
  • Next trigger computation
  • CRUD & migrations
  • Reminder scheduling/cancel

IMPLEMENT NOW using clean architecture and mobile-first responsive UI. Ensure all date/times use epoch milliseconds and respect the user/profile timezone.
