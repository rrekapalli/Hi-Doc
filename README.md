# Hi-Doc

AI-powered chat-based health tracker (Flutter).

## Current Status (Scaffold)

Implemented initial project skeleton:
- Chat UI with rule-based parsing for glucose / weight / BP / medication lines.
- SQLite database service (JSON persistence for entries implemented).
- Models for health entries, vitals, medication, lab results, groups.
- Notification service stub.

## Planned Core Features (per spec)
1. Chat entry & NLP parsing (rule-based now; pluggable AI engine later).
2. Offline-first local storage (SQLite) + cloud sync (Google Drive / OneDrive).
3. Google & Microsoft OAuth via Firebase Auth + AppAuth (Microsoft).
4. Group support (multi member tracking) & tagging entries.
5. Lab report ingestion (PDF/Image) + AI extraction.
6. Insights: charts (fl_chart) & tables with natural language queries.
7. Medication reminders via local notifications.
8. Secure file storage for prescriptions & reports.

## Getting Started

Prerequisites:
- Flutter SDK (>=3.3)
- Dart SDK bundled with Flutter
- Android Studio / Xcode for mobile targets

Install deps:
```
flutter pub get
```

### Environment Setup
1. Install Flutter SDK and add to PATH (run `flutter doctor` until green).
2. (Optional) Create `backend/.env` for overrides. A fallback `.env.root` at repo root is auto-loaded if backend/.env is absent.
3. For backend:
	```
	cd backend
	npm install
	npm run dev
	```
4. Generate JSON code (first time / after model changes):
	```
	dart run build_runner build --delete-conflicting-outputs
	```
5. Run app (Chrome web as example):
	```
	flutter run -d chrome
	```
6. (Optional mobile) Launch emulator then `flutter run`.

VSCode tasks provided (`Terminal > Run Task`) for common steps.

Run (Android emulator / iOS simulator / web):
```
flutter run
```

## Code Generation
Models use json_serializable. After modifying model annotations run:
```
flutter pub run build_runner build --delete-conflicting-outputs
```

## Next Steps
Short-term (foundation polish):
- Wire UI to medications / reminders lists & scheduling via `NotificationService`.
- Basic charts (glucose / weight trend) using `fl_chart`.
- Group management CRUD UI + filtering entries per member.

Medium-term (intelligence & sync):
- AI parsing engine abstraction (replace / augment regex rules).
- Cloud backup & restore (Google Drive / OneDrive) service layer.
- Lab report ingestion (file picker + OCR/AI extraction pipeline stub).

Long-term (insights & sharing):
- Natural language query interface over local data.
- Export / share (PDF summary, CSV, secure link).
- Conflict resolution & incremental sync strategy.

## Authentication Setup
Google (optional Firebase path):
1. (Optional) Create Firebase project & enable Google provider (only if you want Firebase-backed auth state; core app can function with custom backend JWT alone for now).
2. Add Android SHA-1/256 and iOS bundle id if building mobile.
3. Run `flutterfire configure` to generate `firebase_options.dart` and import in `main.dart` (already guarded with try/catch so absence is tolerated).

Microsoft (Azure AD) → Custom JWT flow:
1. Register a public client app in Azure Portal.
2. Add redirect URI (e.g., `com.example.app://auth`) matching `AuthService` configuration.
3. Grant needed delegated permissions (e.g., `User.Read`).
4. Client obtains Microsoft `id_token` via `flutter_appauth`.
5. Flutter sends `id_token` (and access token when available) to backend `/api/auth/microsoft/exchange`.
6. Backend verifies signature against Microsoft JWKS, then issues internal HS256 JWT (`Authorization: Bearer <token>` for subsequent API calls).
7. Store backend base URL and tenant/client IDs in a config location (future: secure storage / .env driven code-gen).

Note: Current implementation does not mint a Firebase custom token for Microsoft users; if unified Firebase auth is desired later, extend backend to produce a Firebase custom token after JWKS verification.


## License
TBD

