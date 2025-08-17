// Simple structured logger with level control and request correlation.
// LOG_LEVEL: error|warn|info|debug (default info). VERBOSE=1 or AI_VERBOSE=1 forces debug.
// Each log line: ISO timestamp, level, msg, optional context as JSON.

export type LevelName = 'error' | 'warn' | 'info' | 'debug';

const LEVEL_ORDER: Record<LevelName, number> = { error: 0, warn: 1, info: 2, debug: 3 };

const envLevel = (process.env.VERBOSE === '1' || process.env.AI_VERBOSE === '1')
  ? 'debug'
  : (process.env.LOG_LEVEL as LevelName) || 'info';

const activeLevel: LevelName = (['error','warn','info','debug'] as LevelName[]).includes(envLevel as LevelName)
  ? envLevel as LevelName : 'info';

function log(level: LevelName, message: string, context?: any) {
  if (LEVEL_ORDER[level] > LEVEL_ORDER[activeLevel]) return;
  
  const timestamp = new Date().toISOString();
  const formattedLevel = level.toUpperCase().padEnd(5);
  const base = `${timestamp} ${formattedLevel} ${message}`;
  
  if (context && Object.keys(context).length) {
    try {
      const safeContext = JSON.stringify(context, (_k, v) => 
        typeof v === 'bigint' ? v.toString() : v
      );
      console.log(base, safeContext);
    } catch (e) {
      console.log(base, '[unserializable-context]', e instanceof Error ? e.message : String(e));
    }
  } else {
    console.log(base);
  }
}

// Helper to redact potentially sensitive fields.
export function redact(obj: any, fields: string[] = ['password','token','authorization','auth']): any {
  if (!obj || typeof obj !== 'object') return obj;
  const clone: any = Array.isArray(obj) ? [] : {};
  for (const k of Object.keys(obj)) {
    if (fields.includes(k.toLowerCase())) {
      clone[k] = '***';
    } else if (obj[k] && typeof obj[k] === 'object') {
      clone[k] = redact(obj[k], fields);
    } else {
      clone[k] = obj[k];
    }
  }
  return clone;
}

export const logger = {
  error: (msg: string, ctx?: any) => log('error', msg, ctx),
  warn: (msg: string, ctx?: any) => log('warn', msg, ctx),
  info: (msg: string, ctx?: any) => log('info', msg, ctx),
  debug: (msg: string, ctx?: any) => log('debug', msg, ctx),
  level: activeLevel,
};
