import { z } from 'zod';
import { logger } from './logger.js';
import { readFileSync } from 'fs';
import { join } from 'path';

// Global verbose flag
const VERBOSE = process.env.AI_VERBOSE === '1' || process.env.VERBOSE === '1';

const AI_SCHEMA = z.object({
  parsed: z.boolean(),
  reply: z.string().optional(),
  entry: z.union([
    z.object({
      type: z.enum(['vital', 'medication', 'labResult', 'note', 'param', 'activity']).optional(),
      category: z.enum(['HEALTH_PARAMS', 'ACTIVITY', 'FOOD', 'MEDICATION', 'SYMPTOMS', 'OTHER']).optional(),
      timestamp: z.number().optional(),
      activity: z.object({
        name: z.string(),
        duration_minutes: z.number().optional(),
        distance_km: z.number().optional(),
        intensity: z.enum(['Low', 'Moderate', 'High']).optional(),
        calories_burned: z.number().optional(),
        notes: z.string().optional(),
      }).optional(),
      vital: z.object({
        vitalType: z.enum(['glucose', 'weight', 'bloodPressure', 'temperature', 'heartRate', 'steps', 'hba1c']).optional(),
        value: z.number().optional(),
        systolic: z.number().optional(),
        diastolic: z.number().optional(),
        unit: z.string().optional(),
      }).optional(),
      param: z.object({
        param_code: z.string().regex(/^[A-Z0-9_]{2,}$/), // must align to param_targets primary key
        value: z.number().optional(),
        unit: z.string().optional(),
        // Optional free-form clarifications (e.g., diastolic for BP when using BP_SYS)
        notes: z.string().optional(),
      }).optional(),
      medication: z.object({
        name: z.string(),
        dose: z.number().optional(),
        doseUnit: z.string().optional(),
        frequencyPerDay: z.number().optional(),
        durationDays: z.number().optional(),
      }).optional(),
      note: z.string().optional(),
    }),
    z.null()
  ]).optional(),
  reasoning: z.string().optional(),
});

export type AiInterpretation = z.infer<typeof AI_SCHEMA>;

// Cached prompts - loaded once at startup
let _messageClassifierPrompt: string | null = null;
let _healthDataEntryPrompt: string | null = null;
let _healthDataTrendPrompt: string | null = null;
let _activityDataEntryPrompt: string | null = null;
let _medicationDataEntryPrompt: string | null = null;

// Prompt cache for better performance
const promptCache = new Map<string, string>();

// Load and cache prompts at startup
function initializePrompts(): void {
  const prompts = [
    'message_classifier_prompt.txt',
    'health_data_entry_prompt.txt',
    'health_data_trend_prompt.txt',
    'activity_data_entry_prompt.txt',
    'medication_data_entry_prompt.txt'
  ];

  for (const promptFile of prompts) {
    try {
      const promptPath = getPromptPath(promptFile);
      const content = readFileSync(promptPath, 'utf-8');
      promptCache.set(promptFile, content);
      logger.debug(`Cached prompt: ${promptFile}`);
    } catch (error) {
      logger.warn(`Failed to load prompt: ${promptFile}`, { error });
    }
  }
}

// Load message classifier prompt from cache or file
function getMessageClassifierPrompt(): string {
  if (!_messageClassifierPrompt) {
    _messageClassifierPrompt = promptCache.get('message_classifier_prompt.txt') || null;
    if (!_messageClassifierPrompt) {
      throw new Error('Message classifier prompt not found in cache');
    }
  }
  return _messageClassifierPrompt;
}

// Helper to get path to prompt file in assets/prompts
function getPromptPath(promptName: string): string {
  return join(process.cwd(), '..', 'assets', 'prompts', promptName);
}

// Load activity data entry prompt from cache
function getActivityDataEntryPrompt(): string {
  if (!_activityDataEntryPrompt) {
    _activityDataEntryPrompt = promptCache.get('activity_data_entry_prompt.txt') || null;
    if (!_activityDataEntryPrompt) {
      throw new Error('Activity data entry prompt not found in cache');
    }
  }
  return _activityDataEntryPrompt;
}

// Load medication data entry prompt from cache
function getMedicationDataEntryPrompt(): string {
  if (!_medicationDataEntryPrompt) {
    _medicationDataEntryPrompt = promptCache.get('medication_data_entry_prompt.txt') || null;
    if (!_medicationDataEntryPrompt) {
      throw new Error('Medication data entry prompt not found in cache');
    }
  }
  return _medicationDataEntryPrompt;
}

// Load health data entry prompt from file
function getHealthDataEntryPrompt(): string {
  if (!_healthDataEntryPrompt) {
    try {
      const promptPath = getPromptPath('health_data_entry_prompt.txt');
      _healthDataEntryPrompt = readFileSync(promptPath, 'utf-8');
      logger.debug('Loaded health data entry prompt from file', { path: promptPath });
    } catch (error) {
      logger.warn('Failed to load health data entry prompt from file, using fallback', { error });
      // Fallback to hardcoded prompt if file loading fails
      _healthDataEntryPrompt = `You are an AI system embedded in a Flutter mobile health tracking app. 
Your task is to parse the user's natural language message and identify if it contains any health-related information that should be stored in the 'health_data' table.

---
Table schema:
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
---

Rules:
1. Identify the type of data (examples: BLOOD_TEST, URINE_TEST, VITALS, ACTIVITY, CALORIE_INTAKE, REPORT, SYMPTOM, OTHER).
2. Determine the category (default 'HEALTH_PARAMS', unless it’s more specific like 'ACTIVITY', 'DIET', etc.).
3. Extract the main numeric or text measurement into 'value'.
4. If the measurement includes a count or amount, store in 'quantity'.
5. Identify the correct 'unit' (examples: mg/dL, bpm, steps, kcal).
6. 'timestamp' should be in UNIX epoch (seconds).
7. 'notes' can contain extra information, like "after lunch" or "during exercise".
8. Use UUID v4 for 'id'.
9. Always return data in JSON exactly matching the health_data fields.

Example:
User: "My blood sugar is 105 mg/dL after breakfast"
AI Output:
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "current_user_id",
  "type": "BLOOD_TEST",
  "category": "HEALTH_PARAMS",
  "value": "105",
  "quantity": null,
  "unit": "mg/dL",
  "timestamp": 1691839200,
  "notes": "after breakfast"
}

Now process the next user message.


---
### Additional Examples for Better Accuracy:

Example 1:
User says: "My blood pressure was 130 over 85 today morning."
Extract:
- type: BLOOD_PRESSURE
- category: VITALS
- value: "130/85"
- unit: "mmHg"
- timestamp: Current time if not provided
- notes: "Reported in morning"

Example 2:
User says: "Yesterday I had fasting blood sugar of 95 mg/dL."
Extract:
- type: BLOOD_SUGAR_FASTING
- category: LAB_TEST
- value: "95"
- unit: "mg/dL"
- timestamp: Yesterday's date at default time
- notes: ""

Example 3:
User says: "Ran 5 kilometers in 30 minutes today evening."
Extract:
- type: RUNNING_DISTANCE
- category: ACTIVITY
- value: "5"
- quantity: "30"
- unit: "km,minutes"
- timestamp: Current date/time (evening if specified)
- notes: ""

Example 4:
User says: "My ESR level came back as 12 mm/hr."
Extract:
- type: ESR
- category: LAB_TEST
- value: "12"
- unit: "mm/hr"
- timestamp: Current time if not provided
- notes: ""

Example 5:
User says: "I consumed about 2200 calories today."
Extract:
- type: CALORIE_INTAKE
- category: NUTRITION
- value: "2200"
- unit: "kcal"
- timestamp: Current time if not provided
- notes: ""

Example 6:
User says: "Troponin test was 0.03 ng/mL."
Extract:
- type: TROPONIN
- category: CARDIAC_MARKERS
- value: "0.03"
- unit: "ng/mL"
- timestamp: Current time
- notes: ""

The extracted values should be mapped directly to the "health_data" table fields without changing the schema.

Now process the next user message.`;
    }
  }
  return _healthDataEntryPrompt;
}

// Load health data trend prompt from file
function getHealthDataTrendPrompt(): string {
  if (!_healthDataTrendPrompt) {
    try {
      const promptPath = getPromptPath('health_data_trend_prompt.txt');
      _healthDataTrendPrompt = readFileSync(promptPath, 'utf-8');
      logger.debug('Loaded health data trend prompt from file', { path: promptPath });
    } catch (error) {
      logger.warn('Failed to load health data trend prompt from file, using fallback', { error });
      // Fallback to hardcoded prompt if file loading fails
      _healthDataTrendPrompt = `You are an AI system in a Flutter health tracking app.
After storing a health parameter in the 'health_data' table, you will ask the user:

"Would you like to see the historic trend for this parameter?"

If the user says "No" → stop and wait for the next input.

If the user says "Yes" →
1. Query 'health_data' for the same user_id, matching 'type' and 'category' of the last stored record.
2. Retrieve the last N (default 20) data points sorted by timestamp ascending.
3. Generate a line or bar chart showing the trend over time.
4. Provide a brief prognosis or interpretation based on the trend:
   - If the values are improving or worsening.
   - If they are within normal ranges (based on standard medical references).
   - Potential recommendations (general wellness advice only, not medical diagnosis).

Return response in JSON:
{
  "chart": "<chart_data_base64_or_json>",
  "prognosis": "Values are gradually improving over the last month, now within normal range."
}`;
    }
  }
  return _healthDataTrendPrompt;
}

// Clear prompt cache (useful for development/testing)
function clearPromptCache(): void {
  _healthDataEntryPrompt = null;
  _healthDataTrendPrompt = null;
  logger.debug('Prompt cache cleared');
}

// Export functions to get prompts (for use in routes.ts)
export { getHealthDataEntryPrompt, getHealthDataTrendPrompt, clearPromptCache };

interface ChatMessage { role: 'system' | 'user' | 'assistant'; content: string; }

const SECOND_PASS_ENABLED = process.env.AI_SECOND_PASS !== '0';
const MAX_TOKENS_CTX = process.env.AI_CTX ? Number(process.env.AI_CTX) : undefined;

// ChatGPT API options
interface ChatOptions {
  temperature?: number;
  top_p?: number;
  max_tokens?: number;
}

function extractFirstJsonBlock(text: string): any {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) throw new Error('No JSON block');
  const slice = text.substring(start, end + 1);
  return JSON.parse(slice);
}

import { ChatGptService } from './chatgpt.js'; // explicit .js retained for ESM build

// Initialize ChatGPT service
const chatGptService = new ChatGptService();

export async function interpretMessage(message: string): Promise<AiInterpretation> {
  if (!process.env.OPENAI_API_KEY) {
    logger.warn('interpretMessage skipped: OPENAI_API_KEY missing', { message });
    return { parsed: false, reply: 'AI not configured (set OPENAI_API_KEY)', reasoning: 'Missing OPENAI_API_KEY' };
  }
  
  const model = process.env.OPENAI_MODEL || 'gpt-3.5-turbo';
  
  // First, use the classifier prompt
  try {
    if (VERBOSE) logger.debug('Using classifier prompt', { message });
    const classifierResponse = await chatGptService.chat([
      { role: 'system', content: getMessageClassifierPrompt() },
      { role: 'user', content: message }
    ], model);
    
    const classification = JSON.parse(classifierResponse);
    
    // If it's a query, return the response directly
    if (classification.parsed === false) {
      if (VERBOSE) logger.debug('Classifier identified query', { classification });
      return classification;
    }
    
    // If it's data entry, route to appropriate prompt
    if (classification.route_to) {
      if (VERBOSE) logger.debug('Classifier routing to specialized prompt', { route: classification.route_to });
      // Use cached prompt if available
      let promptContent: string;
      try {
        const p = classification.route_to;
        // Basic in-process cache leveraging initializePrompts loaded set
        const cacheMap: any = (globalThis as any).__extraPromptCache || ((globalThis as any).__extraPromptCache = new Map());
        if (cacheMap.has(p)) promptContent = cacheMap.get(p);
        else {
          promptContent = readFileSync(join(process.cwd(), 'assets', 'prompts', p), 'utf-8');
          cacheMap.set(p, promptContent);
        }
      } catch (e) {
        logger.warn('Falling back to health data entry prompt for missing cached route prompt', { route: classification.route_to });
        promptContent = getHealthDataEntryPrompt();
      }
      const dataEntryResponse = await chatGptService.chat([
        { role: 'system', content: promptContent },
        { role: 'user', content: classification.original_message }
      ], model);
      
      return JSON.parse(dataEntryResponse);
    }
  } catch (e: any) {
    if (VERBOSE) logger.error('Classifier error, falling back to legacy logic', { error: String(e) });
  }
  
  // Fallback to original interpretation logic if classifier fails
  const attempts: { raw?: string; error?: string }[] = [];
  const MAX_TRIES = 2;
  
  // Legacy keyword detection as fallback
  const activityKeywords = ['walk', 'run', 'swim', 'gym', 'workout', 'exercise', 'yoga', 'cycling', 'jogging', 'km', 'miles', 'steps'];
  const medicationKeywords = ['took', 'take', 'taken', 'dose', 'tablet', 'pill', 'medicine', 'medication', 'insulin', 'injection', 'prescribed', 'mg', 'units'];
  
  const isActivityMessage = activityKeywords.some(keyword => message.toLowerCase().includes(keyword));
  const isMedicationMessage = medicationKeywords.some(keyword => message.toLowerCase().includes(keyword));

  let messages: ChatMessage[] = [
    { 
      role: 'system', 
      content: isActivityMessage ? getActivityDataEntryPrompt() : 
               isMedicationMessage ? getMedicationDataEntryPrompt() :
               getHealthDataEntryPrompt() 
    },
    { role: 'user', content: message }
  ];

  if (VERBOSE) logger.debug('AI interpret start', { message });
  for (let i = 0; i < MAX_TRIES; i++) {
    let raw: string;
    try {
      raw = await chatGptService.chat(messages, model);
      // Replace any remaining <current_timestamp> with current time
      raw = raw.replace(/<current_timestamp>/g, Date.now().toString());
      
      // Parse the JSON
      const parsed = JSON.parse(raw);
      
      // Ensure timestamp is set for all entry types and fix string timestamps
      if (parsed.entry) {
        if (parsed.entry.timestamp === '<current_timestamp>' || typeof parsed.entry.timestamp === 'string') {
          parsed.entry.timestamp = Date.now();
        }
        if (!parsed.entry.timestamp) {
          parsed.entry.timestamp = Date.now();
        }
      }
      
      raw = JSON.stringify(parsed);
    } catch (e: any) {
      if (VERBOSE) logger.error('AI request failure', { error: String(e) });
      return { parsed: false, reply: 'ChatGPT API error', reasoning: String(e.message || e) };
    }
    try {
      const json = extractFirstJsonBlock(raw);
      const parsed = AI_SCHEMA.safeParse(json);
      if (parsed.success) {
        if (VERBOSE) logger.debug('AI success', { attempt: i + 1, result: parsed.data });
        if (parsed.data.entry && !parsed.data.entry.timestamp) {
          parsed.data.entry.timestamp = Date.now();
        }
        return normalizeInterpretation(message, parsed.data, VERBOSE);
      } else {
        attempts.push({ raw, error: parsed.error.message });
        if (VERBOSE) logger.warn('AI schema validation failed', { attempt: i + 1, error: parsed.error.message, sample: raw.slice(0, 300) });
      }
    } catch (e: any) {
      attempts.push({ raw, error: e.message });
      if (VERBOSE) logger.warn('AI JSON parse failed', { attempt: i + 1, error: e.message, sample: raw.slice(0, 300) });
    }
    // Prepare repair prompt for next iteration
    if (i === 0) {
      const last = attempts[attempts.length - 1];
      messages = [
        { role: 'system', content: getHealthDataEntryPrompt() + '\nReturn ONLY compact JSON. No markdown, no commentary.' },
        { role: 'user', content: message },
        { role: 'assistant', content: (last.raw || '').slice(0, 4000) },
        { role: 'user', content: 'The above output failed to parse (' + (last.error || 'unknown') + '). Re-emit ONLY valid JSON.' }
      ];
    }
  }
  const lastErr = attempts[attempts.length - 1];
  if (VERBOSE) logger.error('AI final failure', { lastErr });
  // Second-pass targeted repair attempt (only if enabled and first pass invalid)
  if (SECOND_PASS_ENABLED) {
    try {
      const repairPrompt = `Original user message: "${message.slice(0, 400)}"\nEarlier attempts failed schema: ${JSON.stringify(lastErr).slice(0, 400)}\nRe-emit ONLY valid compact JSON for ONE entry strictly matching the schema. If a numeric health metric (glucose, steps, weight, blood pressure, heart rate, temperature, hba1c) or medication phrase appears, set parsed=true and fill appropriate fields. Otherwise set type=note with the raw message.`;
      const repairMessages: ChatMessage[] = [
        { role: 'system', content: getHealthDataEntryPrompt() + '\nReturn only JSON.' },
        { role: 'user', content: repairPrompt }
      ];
      const repairRaw = await chatGptService.chat(repairMessages, model);
      try {
        const json = extractFirstJsonBlock(repairRaw);
        const parsed = AI_SCHEMA.safeParse(json);
        if (parsed.success) {
          if (parsed.data.entry && !parsed.data.entry.timestamp) parsed.data.entry.timestamp = Date.now();
          return normalizeInterpretation(message, parsed.data, VERBOSE);
        }
      } catch (e2: any) {
        if (VERBOSE) logger.warn('Repair parse failed', { error: e2.message });
      }
    } catch (e: any) {
      if (VERBOSE) logger.warn('Second pass failed', { error: e.message });
    }
  }
  // Salvage heuristics before downgrading to note
  const salvaged = salvageHeuristic(message);
  if (salvaged) {
    if (VERBOSE) logger.warn('Heuristic salvage succeeded');
    return salvaged;
  }
  // As last resort, store as note (never refuse)
  return { parsed: true, reply: 'Noted', entry: { type: 'note', timestamp: Date.now(), note: message.slice(0, 500) }, reasoning: lastErr?.error || 'llm-failure' };
}

// (Regex salvage removed to rely solely on model output)

// Simple status (no secrets) for debugging configuration
export function aiProviderStatus() {
  const openAiKey = process.env.OPENAI_API_KEY;
  const openAiModel = process.env.OPENAI_MODEL || 'gpt-3.5-turbo';
  return {
    openAiConfigured: Boolean(openAiKey),
    openAiModel: openAiKey ? openAiModel : null,
    secondPass: SECOND_PASS_ENABLED
  };
}

// Exposed for tests: ensure interpretation has required fields / downgrade invalid vital.
export function normalizeInterpretation(originalMessage: string, interpretation: AiInterpretation, verbose?: boolean): AiInterpretation {
  if (interpretation.entry?.type === 'vital') {
    const v = interpretation.entry.vital;
    if (!v || !v.vitalType) {
      if (verbose) logger.warn('normalize: vital missing vitalType – downgrading to note (regex disabled)');
      interpretation.entry = { type: 'note', timestamp: Date.now(), note: originalMessage.slice(0, 500) } as any;
    }
  } else if (interpretation.entry?.type === 'param') {
    const p = interpretation.entry.param;
    if (!p || !p.param_code) {
      if (verbose) logger.warn('normalize: param missing param_code – downgrading to note');
      interpretation.entry = { type: 'note', timestamp: Date.now(), note: originalMessage.slice(0, 500) } as any;
    }
  }
  return interpretation;
}

// Lightweight regex salvage for common metrics if model output unusable.
function salvageHeuristic(msg: string): AiInterpretation | null {
  const text = msg.trim();
  const lower = text.toLowerCase();
  // HbA1c
  let m = /(hba1c|a1c)[:\s]*([0-9]{1,2}(?:\.[0-9])?)/i.exec(lower) || /([0-9]{1,2}(?:\.[0-9])?)%?\s*(hba1c|a1c)/i.exec(lower);
  if (m) {
    const val = parseFloat(m[2] || m[1]);
    if (!isNaN(val)) return { parsed: true, reply: `Recorded HBA1C ${val}%`, entry: { type: 'param', category: 'HEALTH_PARAMS', timestamp: Date.now(), param: { param_code: 'HBA1C', value: val, unit: '%' } as any }, reasoning: 'heuristic-salvage' };
  }
  // Steps
  m = /(\b\d{2,6})\s*(steps|step)\b/.exec(lower) || /walk(?:ed)?\s+(\d{2,6})\s*(steps|step)?/.exec(lower);
  if (m) {
    const val = parseInt(m[1], 10);
    if (!isNaN(val)) return { parsed: true, reply: `Recorded ${val} steps`, entry: { type: 'vital', category: 'ACTIVITY', timestamp: Date.now(), vital: { vitalType: 'steps', value: val, unit: 'steps' } as any }, reasoning: 'heuristic-salvage' };
  }
  // Blood pressure
  m = /(\d{2,3})[\s/](\d{2,3})\b/.exec(lower);
  if (m) {
    const sys = parseInt(m[1], 10); const dia = parseInt(m[2], 10);
    if (!isNaN(sys) && !isNaN(dia)) return { parsed: true, reply: `Recorded blood pressure ${sys}/${dia}`, entry: { type: 'param', category: 'HEALTH_PARAMS', timestamp: Date.now(), param: { param_code: 'BP_SYS', value: sys, unit: 'mmHg', notes: `DIA=${dia}` } as any }, reasoning: 'heuristic-salvage' };
  }
  // Glucose - enhanced patterns
  m = /(\d{2,3})\s*(fasting\s*)?(glucose|sugar|mg\/dl)/i.exec(lower) || /(fasting\s*)?(glucose|sugar)[:\s]*(\d{2,3})/i.exec(lower) || /(\d{2,3})\s*(glucose|sugar)/i.exec(lower);
  if (m) {
    const val = parseInt(m[1] || m[3], 10);
    if (!isNaN(val) && val >= 50 && val <= 500) return { parsed: true, reply: `Recorded GLU_FAST ${val} mg/dL`, entry: { type: 'param', category: 'HEALTH_PARAMS', timestamp: Date.now(), param: { param_code: 'GLU_FAST', value: val, unit: 'mg/dL' } as any }, reasoning: 'heuristic-salvage' };
  }
  return null;
}

// Initialize prompts on module load for better performance
initializePrompts();

// Export the initialization function for testing
export { initializePrompts };
