# Health Data Workflow Implementation

This document describes the implementation of the new prompt-based health data workflow in the Hi-Doc Flutter app.

## Overview

The new workflow implements the following user flow:

1. User sends a health-related message
2. System loads `health_data_entry_prompt.txt` and processes the message with LLM
3. System parses LLM output into SQLite `health_data` table structure
4. System saves the parsed record to SQLite
5. System loads `health_data_trend_prompt.txt` and asks user about trend analysis
6. If user selects "Yes", system queries historical data and generates trend analysis
7. If user selects "No", workflow ends

## Files Created/Modified

### New Files Created:
- `assets/prompts/health_data_entry_prompt.txt` - Prompt for parsing health messages (Flutter)
- `assets/prompts/health_data_trend_prompt.txt` - Prompt for trend analysis questions (Flutter)
- `backend/src/assets/health_data_entry_prompt.txt` - Backend copy of health data entry prompt
- `backend/src/assets/health_data_trend_prompt.txt` - Backend copy of health data trend prompt
- `lib/services/prompt_service.dart` - Service to load prompt files from assets
- `lib/models/health_data_entry.dart` - Model matching SQLite health_data schema

### Modified Files:
- `lib/ui/chat/chat_screen.dart` - Added Yes/No buttons for trend analysis
- `lib/providers/chat_provider.dart` - Updated to use new workflow
- `lib/services/ai_service.dart` - Added new methods for prompt-based processing
- `backend/src/ai.ts` - Updated to load prompts from files instead of hardcoded constants
- `backend/src/routes.ts` - Added new API endpoints
- `pubspec.yaml` - Added prompts folder to assets

## New API Endpoints

### POST /api/ai/process-with-prompt
Processes a message with a custom prompt and returns structured health data.

**Request:**
```json
{
  "message": "My blood sugar is 105 mg/dL after breakfast",
  "prompt": "..."
}
```

**Response:**
```json
{
  "reply": "Health data recorded successfully",
  "healthData": {
    "id": "uuid",
    "user_id": "current_user_id",
    "type": "BLOOD_TEST",
    "category": "HEALTH_PARAMS",
    "value": "105",
    "unit": "mg/dL",
    "timestamp": 1691839200,
    "notes": "after breakfast"
  }
}
```

### POST /api/health-data
Saves a health data entry to the SQLite database.

### POST /api/health-data/trend
Generates trend analysis for a specific health parameter type and category.

## Database Schema

The implementation uses the existing `health_data` table:

```sql
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
```

## User Interface Changes

### Chat Screen Updates:
- Added Yes/No buttons that appear after health data is successfully recorded
- Buttons trigger trend analysis workflow
- Updated chat bubbles to show health data recording status
- Fixed deprecated `withOpacity` calls to use `withValues`

### Trend Analysis Flow:
1. After health data is saved, system shows: "Would you like to see the historic trend for this parameter?"
2. User can click "Yes" or "No" buttons
3. If "Yes": System queries historical data and shows trend analysis
4. If "No": Simple acknowledgment message is shown

## Implementation Notes

- The workflow maintains backward compatibility with existing health entry processing
- Prompts are loaded from files and cached for performance:
  - Frontend: Loads from `assets/prompts/` using Flutter's asset system
  - Backend: Loads from `backend/src/assets/` using Node.js file system
- Error handling includes fallbacks for AI processing failures and file loading errors
- The implementation uses the existing backend AI service with new endpoints
- Trend analysis includes basic statistical analysis (increasing/decreasing/stable trends)
- Backend includes a debug endpoint `/api/ai/reload-prompts` to reload prompts without restart

## Testing

To test the implementation:

1. Start the backend server
2. Run the Flutter app
3. Send a health-related message like "My blood pressure is 120/80"
4. Verify the health data is recorded and trend question appears
5. Click "Yes" to test trend analysis or "No" to end the workflow

## Future Enhancements

- Add chart visualization for trend data
- Implement more sophisticated trend analysis algorithms
- Add support for multiple health parameters in a single message
- Enhance prompt templates with more examples
- Add user customization for trend analysis preferences