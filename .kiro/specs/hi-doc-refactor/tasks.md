# Implementation Plan

- [x] 1. Set up repository pattern and database refactoring foundation
  - Create abstract repository interfaces for all data entities
  - Implement base database service with pure SQLite operations
  - Create migration utilities for existing data
  - _Requirements: 1.1, 1.3, 6.1, 6.3_

- [x] 2. Refactor medication management to local-only storage
- [x] 2.1 Create MedicationRepository with pure SQLite operations
  - Implement MedicationRepository class extending base Repository interface
  - Remove all HTTP API calls from medication CRUD operations
  - Add proper error handling and validation for local operations
  - _Requirements: 1.1, 1.2, 6.1, 6.2_

- [x] 2.2 Update MedicationsProvider to use repository pattern
  - Refactor MedicationsProvider to use MedicationRepository instead of HTTP calls
  - Remove web-specific backend API logic
  - Implement optimistic updates for better user experience
  - _Requirements: 1.1, 6.1, 6.2_

- [x] 2.3 Create medication schedule repository and update related services
  - Implement ScheduleRepository for medication schedules and times
  - Update schedule management to use pure SQLite operations
  - Remove backend API dependencies from schedule operations
  - _Requirements: 1.1, 1.2, 6.1_

- [x] 3. Implement health entries and messages local storage
- [x] 3.1 Create HealthEntryRepository with local SQLite operations
  - Implement repository for health entries with proper indexing
  - Add validation and error handling for health data
  - Create efficient queries for health data retrieval and filtering
  - _Requirements: 1.1, 1.2, 6.1_

- [x] 3.2 Create MessageRepository for chat functionality
  - Implement local storage for chat messages and conversations
  - Remove backend API calls for message operations
  - Add proper message threading and profile association
  - _Requirements: 1.1, 1.2, 6.1_

- [x] 3.3 Update ChatProvider to use local repositories
  - Refactor ChatProvider to use MessageRepository and HealthEntryRepository
  - Remove HTTP client dependencies from chat operations
  - Implement offline-first chat functionality
  - _Requirements: 1.1, 5.1, 6.1_

- [x] 4. Implement AI service integration with rate limiting
- [x] 4.1 Create AI rate limiting service with local tracking
  - Implement AIRateLimiter class to track monthly usage in SQLite
  - Add logic to enforce 100 calls per user per month limit
  - Create user-friendly rate limit messaging and feedback
  - _Requirements: 3.3, 3.4, 8.1, 8.2, 8.3_

- [x] 4.2 Implement external AI service client
  - Create AIServiceClient to communicate with Java + Spring Boot backend
  - Remove local AI processing dependencies
  - Add proper error handling for AI service connectivity issues
  - _Requirements: 3.1, 3.2, 5.2, 5.3_

- [x] 4.3 Update ChatProvider to use new AI service with rate limiting
  - Integrate AIRateLimiter into chat message processing
  - Store AI responses locally in SQLite for offline access
  - Add connectivity checks before making AI requests
  - _Requirements: 3.1, 3.2, 3.3, 5.2, 8.1, 8.2_

- [ ] 5. Refactor authentication service for standalone operation
- [ ] 5.1 Implement direct OAuth flows without backend dependency
  - Remove backend token exchange for Microsoft authentication
  - Implement direct Google OAuth integration
  - Store authentication tokens securely using local storage
  - _Requirements: 2.1, 2.2, 7.3_

- [ ] 5.2 Create user management with local storage
  - Implement UserRepository for local user data management
  - Store minimal user profile information locally after authentication
  - Add logic to determine backup provider based on authentication method
  - _Requirements: 2.1, 2.2, 2.3, 7.3_

- [ ] 5.3 Update AuthProvider to use simplified authentication
  - Remove backend API dependencies from authentication flow
  - Implement proper error handling for authentication failures
  - Add clear user feedback for offline authentication attempts
  - _Requirements: 2.1, 2.4, 5.4_

- [ ] 6. Implement cloud backup and restore services
- [ ] 6.1 Create abstract CloudBackupService interface
  - Define common interface for cloud backup operations
  - Add methods for backup, restore, list, and delete operations
  - Include proper error handling and progress tracking
  - _Requirements: 4.1, 4.2, 4.4, 7.1, 7.4_

- [ ] 6.2 Implement Google Drive backup service
  - Create GoogleDriveBackupService using googleapis package
  - Implement database file encryption before upload
  - Add proper authentication and permission handling
  - _Requirements: 4.1, 4.4, 7.1, 7.4_

- [ ] 6.3 Implement OneDrive backup service (priority)
  - Create OneDriveBackupService using microsoft_graph package
  - Implement secure file upload and download operations
  - Add proper error handling for OneDrive API operations
  - _Requirements: 4.2, 4.4, 7.2, 7.4_

- [ ] 6.4 Create backup/restore UI and user flows
  - Add backup and restore options to settings screen
  - Implement progress indicators for backup/restore operations
  - Add conflict resolution UI for restore operations
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 7. Implement offline-first UI and connectivity handling
- [ ] 7.1 Create ConnectivityService for network status monitoring
  - Implement service to monitor network connectivity status
  - Add listeners for connectivity changes
  - Provide connectivity status to other services and UI components
  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 7.2 Update all providers for offline-first operation
  - Remove HTTP dependencies from all remaining providers
  - Implement optimistic updates with proper error handling
  - Add connectivity awareness to all network-dependent operations
  - _Requirements: 5.1, 5.2, 6.1, 6.2_

- [ ] 7.3 Add offline/online status indicators to UI
  - Create status indicators for AI and authentication features
  - Add clear messaging when features are unavailable offline
  - Implement graceful degradation for offline scenarios
  - _Requirements: 5.2, 5.3, 5.4_

- [ ] 8. Remove backend dependencies and clean up configuration
- [ ] 8.1 Remove Node.js backend API configuration
  - Remove backend URL configuration from app config
  - Clean up HTTP client service dependencies
  - Remove unused backend-related imports and code
  - _Requirements: 6.2, 6.3_

- [ ] 8.2 Update app configuration for standalone operation
  - Update AppConfig to remove backend-specific settings
  - Add configuration for AI service endpoint
  - Configure cloud storage service settings
  - _Requirements: 6.2, 6.3_

- [ ] 8.3 Clean up unused dependencies and imports
  - Remove unused HTTP client dependencies
  - Clean up backend-related service imports
  - Update pubspec.yaml to remove unnecessary packages
  - _Requirements: 6.2, 6.3_

- [ ] 9. Implement comprehensive testing for offline functionality
- [ ] 9.1 Create unit tests for repository layer
  - Write tests for all repository implementations
  - Test error handling and edge cases
  - Verify proper SQLite operations and data integrity
  - _Requirements: 1.1, 1.2, 6.1_

- [ ] 9.2 Create integration tests for offline scenarios
  - Test complete user workflows in offline mode
  - Verify data persistence and retrieval
  - Test backup and restore functionality
  - _Requirements: 5.1, 4.1, 4.2_

- [ ] 9.3 Create tests for AI rate limiting and connectivity handling
  - Test AI rate limiting logic and enforcement
  - Verify proper handling of connectivity changes
  - Test graceful degradation of online features
  - _Requirements: 3.3, 3.4, 5.2, 5.3, 8.1, 8.2_

- [ ] 10. Performance optimization and security hardening
- [ ] 10.1 Optimize database operations and queries
  - Add proper indexes for frequently queried data
  - Optimize SQLite queries for better performance
  - Implement efficient batch operations where needed
  - _Requirements: 1.1, 1.2_

- [ ] 10.2 Implement data encryption and security measures
  - Add encryption for local SQLite database
  - Implement secure storage for authentication tokens
  - Add encryption for cloud backup files
  - _Requirements: 7.3, 7.4_

- [ ] 10.3 Conduct security audit and performance testing
  - Review all security implementations
  - Test performance under various data loads
  - Verify proper memory management and resource cleanup
  - _Requirements: 7.3, 7.4_