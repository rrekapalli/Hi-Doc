import 'dotenv/config';
import request from 'supertest';
import express from 'express';
import cors from 'cors';
import router from '../routes.js';
import { migrate } from '../db.js';
import { normalizeInterpretation, AiInterpretation } from '../ai.js';
import { signToken } from '../jwtUtil.js';

async function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json());
  migrate();
  app.use(router);
  return app;
}

(async () => {
  const app = await createApp();
  const token = await signToken({ uid: 'test-user', email: 'test@example.com' });
  // Ensure user exists (foreign key constraints)
  const dbMod = await import('../db.js');
  dbMod.db.prepare('INSERT OR IGNORE INTO users (id, name, email) VALUES (?,?,?)').run('test-user', 'Test User', 'test@example.com');

  let pass = 0, fail = 0;
  function log(ok: boolean, name: string, detail?: any) {
    if (ok) { 
      pass++; 
      console.log('✅', name); 
    } else { 
      fail++; 
      console.error('❌', name); 
      if (detail) {
        console.error('   Details:', detail);
      }
    }
  }

  try {
    // Create health record
    const hRes = await request(app).post('/api/health').set('Authorization', `Bearer ${token}`).send({ 
      type: 'glucose', 
      value: '95', 
      unit: 'mg/dL',
      conversation_id: 'default-conversation'
    });
    log(hRes.status === 201, 'create health');

  const listRes = await request(app).get('/api/health').set('Authorization', `Bearer ${token}`);
  log(listRes.status === 200 && Array.isArray(listRes.body.items) && listRes.body.items.length >= 1, 'list health');

    // Medication create
    const mRes = await request(app).post('/api/medications').set('Authorization', `Bearer ${token}`).send({ 
      name: 'Paracetamol', 
      dosage: '500mg',
      conversation_id: 'default-conversation'
    });
    log(mRes.status === 201, 'create medication');

    const medsList = await request(app).get('/api/medications').set('Authorization', `Bearer ${token}`);
    log(medsList.status === 200 && medsList.body.length >= 1, 'list medications');

  // Normalization test: simulate AI returning type=vital without vital.vitalType
  const bad: AiInterpretation = { parsed: true, reply: 'ok', entry: { type: 'vital', timestamp: Date.now(), vital: { /* missing vitalType */ value: 123 as any } as any } };
  const fixed = normalizeInterpretation('glucose 123', bad, true);
  log(fixed.entry?.type !== 'vital' || !!fixed.entry?.vital?.vitalType, 'normalize missing vitalType');

  // Param targets upsert
  const ptRes = await request(app).put('/api/param-targets/glucose').set('Authorization', `Bearer ${token}`).send({ target_min: 70, target_max: 140, preferred_unit: 'mg/dL' });
  log(ptRes.status === 200 && ptRes.body.param_code === 'glucose', 'upsert param target');
  const ptList = await request(app).get('/api/param-targets').set('Authorization', `Bearer ${token}`);
  log(ptList.status === 200 && Array.isArray(ptList.body) && ptList.body.length >= 1, 'list param targets');

  // Messages listing (should include previous health creation? not yet; simulate via interpret-store would require model). Just ensure endpoint works empty.
  const msgs = await request(app).get('/api/messages').set('Authorization', `Bearer ${token}`);
  log(msgs.status === 200, 'list messages');


  } catch (e: any) {
    log(false, 'unexpected error', e.message);
  } finally {
    console.log(`\nPass: ${pass}  Fail: ${fail}`);
    if (fail > 0) process.exit(1);
  }
})();
