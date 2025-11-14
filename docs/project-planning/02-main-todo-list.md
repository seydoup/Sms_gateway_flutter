# SMS Gateway Reliability - Main TODO List

**Project Start Date:** 2025-11-14
**Last Updated:** 2025-11-14
**Status:** Planning Phase

---

## 📌 Project Status Overview

| Milestone | Status | Progress | Priority | Estimated Effort |
|-----------|--------|----------|----------|------------------|
| Milestone 1: Database Foundation | ⏳ Pending | 0% | MUST HAVE | 2-3 hours |
| Milestone 2: Retry Logic | ⏳ Pending | 0% | MUST HAVE | 3-4 hours |
| Milestone 3: Delivery Tracking | ⏳ Pending | 0% | HIGH | 2-3 hours |
| Milestone 4: Production Hardening | ⏳ Pending | 0% | MEDIUM | 3-4 hours |

**Legend:** ⏳ Pending | 🚧 In Progress | ✅ Completed | ⏸️ Blocked | ❌ Cancelled

---

## 🎯 Milestone 1: Database Foundation

**Status:** ⏳ Pending
**Duration:** 2-3 hours
**Dependencies:** None
**Target Completion:** TBD

### Tasks

- [ ] **1.1 Add Dependencies**
  - [ ] Add `sqflite: ^2.3.0` to `pubspec.yaml`
  - [ ] Add `path: ^1.8.3` to `pubspec.yaml`
  - [ ] Run `flutter pub get`
  - [ ] Verify dependencies installed successfully

- [ ] **1.2 Create Database Service**
  - [ ] Create `lib/services/sms_queue_database.dart`
  - [ ] Define database schema (tables: sms_queue, error_logs)
  - [ ] Implement database initialization
  - [ ] Implement database version migration logic
  - [ ] Add database helper methods (open, close, reset)

- [ ] **1.3 Implement SMS Queue CRUD**
  - [ ] Create `lib/models/queued_sms.dart` model
  - [ ] Implement `insertSms()` method
  - [ ] Implement `updateSmsStatus()` method
  - [ ] Implement `getSmsById()` method
  - [ ] Implement `getPendingSms()` method
  - [ ] Implement `getFailedSms()` method
  - [ ] Implement `deleteSms()` method
  - [ ] Add indexes for performance

- [ ] **1.4 Migrate Existing History**
  - [ ] Create migration script to convert SharedPreferences to SQLite
  - [ ] Test migration with existing data
  - [ ] Add rollback capability
  - [ ] Update `lib/services/sms_listeneing.dart` to use new database

- [ ] **1.5 Testing**
  - [ ] Create `test/services/sms_queue_database_test.dart`
  - [ ] Write unit tests for all CRUD operations
  - [ ] Test database migration
  - [ ] Test concurrent access scenarios
  - [ ] Verify database file location and permissions

- [ ] **1.6 Validation**
  - [ ] Run app and send test SMS
  - [ ] Verify SMS stored in SQLite database
  - [ ] Check database file exists at correct path
  - [ ] Verify history UI still displays messages
  - [ ] Test app restart - data persists

**Completion Criteria:**
- ✅ All SMS messages stored in SQLite
- ✅ Database survives app restart
- ✅ All unit tests passing
- ✅ No regression in existing functionality

---

## 🔄 Milestone 2: Retry Logic

**Status:** ⏳ Pending
**Duration:** 3-4 hours
**Dependencies:** Milestone 1 ✅
**Target Completion:** TBD

### Tasks

- [ ] **2.1 Add Network Monitoring**
  - [ ] Add `connectivity_plus: ^5.0.2` to `pubspec.yaml`
  - [ ] Create `lib/services/network_monitor.dart`
  - [ ] Implement network status detection (WiFi/Mobile/None)
  - [ ] Implement network change listener
  - [ ] Add network status stream

- [ ] **2.2 Create Retry Manager**
  - [ ] Create `lib/models/retry_config.dart` model
  - [ ] Create `lib/services/retry_manager.dart`
  - [ ] Implement exponential backoff algorithm (5s, 15s, 60s, 300s)
  - [ ] Implement retry count tracking
  - [ ] Implement max retry limit (default: 5 attempts)
  - [ ] Add configurable retry delays

- [ ] **2.3 Implement Queue Processor**
  - [ ] Create background queue processor in `retry_manager.dart`
  - [ ] Implement pending SMS fetcher
  - [ ] Implement retry scheduler
  - [ ] Add network-aware processing (pause when offline)
  - [ ] Implement auto-resume when network restored

- [ ] **2.4 Update SMS Listener**
  - [ ] Modify `lib/services/sms_listeneing.dart`
  - [ ] Change `_sendSmsToEndpoint()` to queue on failure
  - [ ] Add immediate send attempt if online
  - [ ] Queue to database if send fails
  - [ ] Remove old SharedPreferences history save

- [ ] **2.5 Add Retry UI Indicators**
  - [ ] Update `lib/pages/sms_history_page.dart`
  - [ ] Add retry count display
  - [ ] Add "pending retry" status indicator
  - [ ] Add next retry time display
  - [ ] Add color coding (green=delivered, yellow=retrying, red=failed)

- [ ] **2.6 Testing**
  - [ ] Create `test/services/retry_manager_test.dart`
  - [ ] Test exponential backoff timing
  - [ ] Test max retry limit
  - [ ] Test network-aware queuing
  - [ ] Integration test: offline → send SMS → online → verify delivery

- [ ] **2.7 Validation**
  - [ ] Turn off WiFi/mobile data
  - [ ] Send test SMS
  - [ ] Verify SMS queued in database with status "pending"
  - [ ] Turn on network
  - [ ] Verify automatic retry occurs
  - [ ] Check retry count increments
  - [ ] Verify exponential backoff delays (use logs)

**Completion Criteria:**
- ✅ SMS queued when network unavailable
- ✅ Automatic retry with exponential backoff
- ✅ Network restoration triggers auto-retry
- ✅ UI shows retry status accurately
- ✅ No message loss during network outages

---

## 📊 Milestone 3: Delivery Tracking

**Status:** ⏳ Pending
**Duration:** 2-3 hours
**Dependencies:** Milestone 2 ✅
**Target Completion:** TBD

### Tasks

- [ ] **3.1 Enhanced Status Tracking**
  - [ ] Update database schema to track detailed status per endpoint
  - [ ] Add `delivery_status` enum (pending, in_progress, delivered, failed, retrying)
  - [ ] Add `last_attempt_at` timestamp
  - [ ] Add `error_message` field
  - [ ] Add `http_status_code` field
  - [ ] Create migration script for schema update

- [ ] **3.2 Implement Notifications**
  - [ ] Add `flutter_local_notifications: ^17.0.0` to `pubspec.yaml`
  - [ ] Create `lib/services/notification_service.dart`
  - [ ] Configure Android notification channel
  - [ ] Implement "delivery failed" notification
  - [ ] Implement "all retries exhausted" notification
  - [ ] Add notification tap handler (open failed messages page)

- [ ] **3.3 Asynchronous Endpoint Processing**
  - [ ] Modify `lib/services/sms_listeneing.dart:_processSmsMessage()`
  - [ ] Change from sequential loop to `Future.wait()`
  - [ ] Process all endpoints in parallel
  - [ ] Collect all results concurrently
  - [ ] Handle timeout per endpoint (not global)

- [ ] **3.4 Create Failed Messages UI**
  - [ ] Create `lib/pages/failed_messages_page.dart`
  - [ ] Create `lib/widgets/failed_message_card.dart`
  - [ ] Display failed SMS with error details
  - [ ] Add "Retry Now" button per message
  - [ ] Add "Retry All" button
  - [ ] Add "Delete Failed" button
  - [ ] Show error message and HTTP status code

- [ ] **3.5 Structured Error Logging**
  - [ ] Create `lib/models/error_log_entry.dart`
  - [ ] Create `lib/services/error_logger.dart`
  - [ ] Log all HTTP errors with full context
  - [ ] Include stack traces for exceptions
  - [ ] Add error log viewer page
  - [ ] Implement log rotation (keep last 1000 entries)

- [ ] **3.6 Testing**
  - [ ] Test parallel endpoint processing
  - [ ] Test notifications appear on failure
  - [ ] Test manual retry from failed messages page
  - [ ] Test error logging captures all details
  - [ ] Integration test: multiple endpoints, one fails

- [ ] **3.7 Validation**
  - [ ] Configure endpoint with unreachable URL
  - [ ] Send test SMS
  - [ ] Verify notification appears
  - [ ] Check failed messages page shows failure
  - [ ] Verify error log contains details
  - [ ] Test manual retry button works
  - [ ] Verify parallel processing with 3+ endpoints

**Completion Criteria:**
- ✅ Notifications sent on delivery failure
- ✅ Failed messages accessible in UI
- ✅ Manual retry works correctly
- ✅ Parallel processing speeds up delivery
- ✅ Detailed error logs available for debugging

---

## 🛡️ Milestone 4: Production Hardening

**Status:** ⏳ Pending
**Duration:** 3-4 hours
**Dependencies:** Milestone 3 ✅
**Target Completion:** TBD

### Tasks

- [ ] **4.1 SMS Handler Synchronization**
  - [ ] Add `synchronized: ^3.1.0` to `pubspec.yaml`
  - [ ] Create mutex for database writes
  - [ ] Protect `insertSms()` with lock
  - [ ] Protect `updateSmsStatus()` with lock
  - [ ] Test concurrent SMS handling (simulate burst)

- [ ] **4.2 Background Task Reliability**
  - [ ] Add `workmanager: ^0.5.2` to `pubspec.yaml`
  - [ ] Create `lib/services/background_worker.dart`
  - [ ] Implement WorkManager task for retry queue processing
  - [ ] Configure periodic task (every 15 minutes)
  - [ ] Register background task in Android native code
  - [ ] Test background processing when app killed

- [ ] **4.3 Health Dashboard**
  - [ ] Create `lib/pages/health_dashboard.dart`
  - [ ] Create `lib/widgets/health_metric_card.dart`
  - [ ] Create `lib/services/health_metrics.dart`
  - [ ] Display queue size (pending messages)
  - [ ] Display success rate (last 24 hours)
  - [ ] Display last error with timestamp
  - [ ] Display network status
  - [ ] Display retry queue processing status

- [ ] **4.4 Error Categorization**
  - [ ] Create `lib/models/error_category.dart` enum
  - [ ] Create `lib/services/error_classifier.dart`
  - [ ] Classify network errors (timeout, DNS, connection refused)
  - [ ] Classify HTTP errors (4xx client, 5xx server)
  - [ ] Classify app errors (permissions, storage)
  - [ ] Apply different retry strategies per category

- [ ] **4.5 Load Testing**
  - [ ] Create test script to simulate SMS bursts
  - [ ] Test with 50 SMS sent in 10 seconds
  - [ ] Verify no data loss
  - [ ] Verify no database corruption
  - [ ] Check memory usage under load
  - [ ] Verify UI remains responsive

- [ ] **4.6 Testing**
  - [ ] Test concurrent SMS handling (no race conditions)
  - [ ] Test background worker survives app kill
  - [ ] Test health dashboard accuracy
  - [ ] Test error classification logic
  - [ ] Load test with 100+ SMS

- [ ] **4.7 Validation**
  - [ ] Send 50 SMS rapidly
  - [ ] Verify all SMS queued correctly
  - [ ] Force-close app (swipe away)
  - [ ] Send SMS to device
  - [ ] Verify background worker still forwards SMS
  - [ ] Check health dashboard shows accurate metrics
  - [ ] Verify no crashes or data corruption

**Completion Criteria:**
- ✅ No data loss under concurrent load
- ✅ Background processing works when app killed
- ✅ Health dashboard provides accurate metrics
- ✅ Error categorization improves retry logic
- ✅ Load test passes (100+ SMS, no data loss)

---

## 📝 Implementation Log

Detailed implementation logs for each work session will be stored in `/docs/implementation-logs/` with filenames:
- `YYYY-MM-DD-session-N.md`

Example: `2025-11-14-session-1.md`

---

## 🚧 Blockers & Risks

| ID | Description | Impact | Mitigation | Status |
|----|-------------|--------|------------|--------|
| - | None identified yet | - | - | - |

---

## 📈 Progress Tracking

### Overall Progress: 0%

```
Milestone 1: [░░░░░░░░░░] 0%
Milestone 2: [░░░░░░░░░░] 0%
Milestone 3: [░░░░░░░░░░] 0%
Milestone 4: [░░░░░░░░░░] 0%
```

### Time Tracking

| Milestone | Estimated | Actual | Variance |
|-----------|-----------|--------|----------|
| Milestone 1 | 2-3 hours | - | - |
| Milestone 2 | 3-4 hours | - | - |
| Milestone 3 | 2-3 hours | - | - |
| Milestone 4 | 3-4 hours | - | - |
| **Total** | **10-14 hours** | **-** | **-** |

---

## ✅ Next Actions

**Immediate next steps (pending user approval):**

1. [ ] **User reviews recommendations** (`01-recommendations-and-roadmap.md`)
2. [ ] **User approves milestones** (all 4, or subset)
3. [ ] **User confirms timeline** (incremental vs. all-at-once)
4. [ ] **Begin Milestone 1 implementation**

**Waiting for:**
- User decision on which milestones to implement
- User feedback on timeline and constraints
- User confirmation to proceed

---

## 📚 Related Documentation

- **Initial Analysis:** `/docs/project-planning/00-initial-analysis.md`
- **Recommendations:** `/docs/project-planning/01-recommendations-and-roadmap.md`
- **Milestone Details:** `/docs/project-planning/milestones/`
- **Implementation Logs:** `/docs/implementation-logs/`
- **Technical Specs:** `/docs/technical-specs/`
- **Test Plans:** `/docs/testing/`

---

**Last Updated:** 2025-11-14
**Next Review:** After user approval
