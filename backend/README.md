# Hi-Doc Backend (SQLite)

Lightweight REST API using Express + better-sqlite3.

## Features
- Users table auto-upsert on Microsoft token stub exchange.
- CRUD for health_data (create/list/get/delete).
- Schema per provided spec (users, health_data, medications, reports, reminders, group_members).

## Run
Install deps then start dev server:
```
npm install
npm run dev
```
Database file: `hi_doc.db` in project root (override with `DB_FILE`).

## Microsoft Auth Stub
POST /api/auth/microsoft/exchange
Body: `{ "id_token": "<fake or real JWT>" }`
Returns base64 token (NOT SECURE). Replace with proper validation + JWT issuing.

## Health Data
Create:
```
POST /api/health
Authorization: Bearer <token>
{ "type": "glucose", "value": "98", "unit": "mg/dL" }
```
List:
```
GET /api/health?limit=20
Authorization: Bearer <token>
```
Get one:
```
GET /api/health/:id
```
Delete:
```
DELETE /api/health/:id
```

## TODO
- Secure JWT with signing key.
- Add remaining CRUD endpoints (medications, reports, reminders, groups).
- Add pagination & filtering.
- Add proper Microsoft token signature verification.
