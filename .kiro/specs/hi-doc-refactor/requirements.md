# Requirements Document

## Introduction

The Hi-Doc application needs to be re-architected from its current Flutter + Node.js backend architecture to a fully standalone/offline Flutter application. The goal is to eliminate dependencies on the custom backend for CRUD operations and make the app work primarily with local SQLite storage. The only external dependencies should be OAuth authentication (Google/Microsoft [first priority]) and AI services through a separate Java + Spring Boot backend.

## Requirements

### Requirement 1

**User Story:** As a user, I want all my health data to be stored locally on my device, so that I can access and manage my information without requiring an internet connection.

#### Acceptance Criteria

1. WHEN the app starts THEN it SHALL use only local SQLite database for all CRUD operations
2. WHEN I create profiles, activities, messages, or health records THEN they SHALL be stored locally in SQLite
3. WHEN I access any app feature THEN it SHALL work without internet connectivity except for authentication and AI features
4. WHEN examining data storage THEN there SHALL be no dependencies on the custom Node.js backend for local data operations

### Requirement 2

**User Story:** As a user, I want to authenticate using my Google or Microsoft account, so that I can securely access the app and enable cloud backup features.

#### Acceptance Criteria

1. WHEN I choose to sign in THEN the app SHALL support OAuth authentication for Microsoft accounts (first priority) and Google
2. WHEN authentication is successful THEN minimal user profile information SHALL be stored locally
3. WHEN I am authenticated THEN the app SHALL determine my backup provider based on my login method (Google Drive or OneDrive)
4. WHEN I am offline THEN authentication features SHALL be unavailable with clear user feedback

### Requirement 3

**User Story:** As a user, I want to use AI features for health insights and chat functionality, so that I can get intelligent assistance with my health tracking.

#### Acceptance Criteria

1. WHEN I make an AI request THEN it SHALL be routed to an external Java + Spring Boot backend
2. WHEN I receive AI responses THEN they SHALL be stored locally in SQLite for offline access
3. WHEN I make AI requests THEN the system SHALL enforce a monthly rate limit of 100 calls per user per month
4. WHEN I exceed the rate limit THEN the system SHALL provide clear feedback and prevent additional requests until the next month

### Requirement 4

**User Story:** As a user, I want to backup my health data to the cloud and restore it on multiple devices, so that I don't lose my information and can access it anywhere.

#### Acceptance Criteria

1. WHEN I am authenticated with Google THEN I SHALL be able to backup my SQLite database to Google Drive
2. WHEN I am authenticated with Microsoft THEN I SHALL be able to backup my SQLite database to OneDrive
3. WHEN I want to restore data THEN I SHALL be able to recover my database from cloud storage on any device
4. WHEN backup/restore conflicts occur THEN the system SHALL handle them gracefully with user guidance

### Requirement 5

**User Story:** As a user, I want the app to work seamlessly offline while providing clear feedback about online features, so that I understand what functionality is available at any time.

#### Acceptance Criteria

1. WHEN I am offline THEN all screens SHALL load and operate using local data
2. WHEN I attempt to use AI features offline THEN the app SHALL provide clear feedback about connectivity requirements
3. WHEN I attempt authentication offline THEN the app SHALL provide clear feedback about connectivity requirements
4. WHEN connectivity is restored THEN the app SHALL seamlessly enable online features

### Requirement 6

**User Story:** As a developer, I want all service classes refactored to use local SQLite instead of HTTP APIs, so that the app architecture supports the offline-first approach.

#### Acceptance Criteria

1. WHEN examining service classes THEN they SHALL use local SQLite operations instead of HTTP API calls
2. WHEN reviewing the codebase THEN there SHALL be no backend API configuration for local endpoints
3. WHEN examining data access patterns THEN they SHALL follow consistent local storage patterns
4. WHEN services need external connectivity THEN it SHALL only be for authentication and AI features

### Requirement 7

**User Story:** As a developer, I want secure and efficient backup/restore services, so that user data is protected and synchronization works reliably.

#### Acceptance Criteria

1. WHEN implementing backup services THEN they SHALL use googleapis package for Google Drive integration
2. WHEN implementing backup services THEN they SHALL use microsoft_graph package for OneDrive integration
3. WHEN handling user data THEN all local data SHALL be encrypted for privacy protection
4. WHEN performing backup/restore operations THEN they SHALL be secure and handle errors gracefully

### Requirement 8

**User Story:** As a developer, I want proper AI rate limiting and local tracking, so that usage limits are enforced and users have visibility into their consumption.

#### Acceptance Criteria

1. WHEN implementing AI rate limiting THEN usage counters and timestamps SHALL be stored in local SQLite
2. WHEN a user makes an AI request THEN the system SHALL check local limits before making external calls
3. WHEN rate limits are reached THEN the system SHALL prevent requests and provide clear user feedback
4. WHEN examining rate limiting logic THEN it SHALL be accurate and handle edge cases properly