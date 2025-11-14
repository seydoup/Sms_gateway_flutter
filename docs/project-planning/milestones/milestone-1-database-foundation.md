# Milestone 1: Database Foundation

**Status:** ⏳ Pending
**Priority:** MUST HAVE
**Estimated Effort:** 2-3 hours
**Dependencies:** None
**Start Date:** TBD
**Completion Date:** TBD

---

## 🎯 Objective

Replace SharedPreferences with SQLite for reliable, transactional storage of SMS queue and history. This provides the foundation for retry logic and delivery tracking.

---

## 🎁 Deliverables

1. ✅ SQLite database with proper schema
2. ✅ SMS queue CRUD operations
3. ✅ Migration from SharedPreferences to SQLite
4. ✅ Unit tests for database operations
5. ✅ Verified data persistence across app restarts

---

## 📋 Detailed Tasks

### Task 1.1: Add Dependencies (15 min)

**Files to Modify:**
- `pubspec.yaml`

**Changes:**
```yaml
dependencies:
  sqflite: ^2.3.0
  path: ^1.8.3
```

**Steps:**
1. Add dependencies to `pubspec.yaml`
2. Run `flutter pub get`
3. Verify no dependency conflicts
4. Check Flutter/Dart SDK compatibility

**Validation:**
- [ ] Dependencies installed successfully
- [ ] No build errors

---

### Task 1.2: Create Database Service (45 min)

**Files to Create:**
- `lib/services/sms_queue_database.dart`

**Database Schema:**

```sql
-- SMS Queue Table
CREATE TABLE sms_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  sender TEXT NOT NULL,
  content TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  created_at TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  retry_count INTEGER DEFAULT 0,
  last_attempt_at TEXT,
  next_retry_at TEXT,
  error_message TEXT,
  http_status_code INTEGER,
  endpoint_results TEXT -- JSON array
);

-- Indexes for performance
CREATE INDEX idx_status ON sms_queue(status);
CREATE INDEX idx_next_retry ON sms_queue(next_retry_at);
CREATE INDEX idx_created_at ON sms_queue(created_at);

-- Error Logs Table
CREATE TABLE error_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  timestamp TEXT NOT NULL,
  error_type TEXT NOT NULL,
  error_message TEXT NOT NULL,
  stack_trace TEXT,
  context TEXT, -- JSON with additional context
  sms_id INTEGER,
  FOREIGN KEY (sms_id) REFERENCES sms_queue(id)
);

CREATE INDEX idx_error_timestamp ON error_logs(timestamp);
```

**Implementation:**
```dart
class SmsQueueDatabase {
  static final SmsQueueDatabase instance = SmsQueueDatabase._init();
  static Database? _database;

  SmsQueueDatabase._init();

  Future<Database> get database async { ... }
  Future<Database> _initDB(String filePath) async { ... }
  Future<void> _createDB(Database db, int version) async { ... }
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async { ... }
  Future<void> close() async { ... }
}
```

**Validation:**
- [ ] Database file created at correct path
- [ ] All tables exist with correct schema
- [ ] Indexes created successfully

---

### Task 1.3: Implement SMS Queue CRUD (45 min)

**Files to Create:**
- `lib/models/queued_sms.dart`

**Model Definition:**
```dart
class QueuedSms {
  final int? id;
  final String sender;
  final String content;
  final String timestamp;
  final DateTime createdAt;
  final SmsStatus status;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final String? errorMessage;
  final int? httpStatusCode;
  final List<EndpointResult>? endpointResults;

  // toMap(), fromMap(), copyWith() methods
}

enum SmsStatus {
  pending,
  inProgress,
  delivered,
  failed,
  retrying
}
```

**Files to Modify:**
- `lib/services/sms_queue_database.dart`

**CRUD Methods:**
```dart
Future<int> insertSms(QueuedSms sms) async { ... }
Future<QueuedSms?> getSmsById(int id) async { ... }
Future<List<QueuedSms>> getPendingSms() async { ... }
Future<List<QueuedSms>> getFailedSms() async { ... }
Future<List<QueuedSms>> getSmsForRetry() async { ... }
Future<int> updateSmsStatus(int id, SmsStatus status, {
  String? errorMessage,
  int? httpStatusCode,
  DateTime? nextRetryAt,
}) async { ... }
Future<int> deleteSms(int id) async { ... }
Future<int> deleteOldDeliveredSms(Duration retention) async { ... }
```

**Validation:**
- [ ] All CRUD operations work correctly
- [ ] Queries return expected results
- [ ] Indexes improve query performance

---

### Task 1.4: Migrate Existing History (30 min)

**Files to Modify:**
- `lib/services/sms_listeneing.dart`

**Migration Steps:**
```dart
Future<void> migrateHistoryToSqlite() async {
  // 1. Load existing history from SharedPreferences
  final prefs = await PreferencesService.getInstance();
  final historyJson = prefs.getString('sms_history');

  // 2. Parse and convert to QueuedSms objects
  final List<QueuedSms> messages = _parseHistory(historyJson);

  // 3. Insert into SQLite
  final db = SmsQueueDatabase.instance;
  for (var sms in messages) {
    await db.insertSms(sms);
  }

  // 4. Backup old data (optional)
  await prefs.setString('sms_history_backup', historyJson);

  // 5. Clear old SharedPreferences key
  await prefs.remove('sms_history');
}
```

**Rollback Plan:**
- Keep backup in SharedPreferences for 7 days
- Provide manual rollback function if needed

**Validation:**
- [ ] All existing messages migrated
- [ ] UI shows same history after migration
- [ ] No data loss

---

### Task 1.5: Update SMS Listener (30 min)

**Files to Modify:**
- `lib/services/sms_listeneing.dart`

**Changes:**
1. Replace `_saveToHistory()` with database insert
2. Replace `loadSmsHistory()` with database query
3. Update status after send attempt
4. Remove SharedPreferences history operations

**Example:**
```dart
Future<void> _processSmsMessage(SmsMessage message) async {
  // Create queued SMS entry
  final queuedSms = QueuedSms(
    sender: message.address ?? 'Unknown',
    content: message.body ?? '',
    timestamp: DateTime.now().toIso8601String(),
    createdAt: DateTime.now(),
    status: SmsStatus.pending,
    retryCount: 0,
  );

  // Insert into database
  final db = SmsQueueDatabase.instance;
  final smsId = await db.insertSms(queuedSms);

  // Attempt to send
  final results = await _sendToAllEndpoints(queuedSms);

  // Update status based on results
  final allSuccess = results.every((r) => r.status == 'success');
  await db.updateSmsStatus(
    smsId,
    allSuccess ? SmsStatus.delivered : SmsStatus.failed,
    // ... other params
  );
}
```

**Validation:**
- [ ] New SMS stored in database
- [ ] Status updated correctly
- [ ] No SharedPreferences calls for history

---

### Task 1.6: Testing (45 min)

**Files to Create:**
- `test/services/sms_queue_database_test.dart`

**Test Cases:**
```dart
void main() {
  group('SmsQueueDatabase', () {
    test('should insert and retrieve SMS', () async { ... });
    test('should update SMS status', () async { ... });
    test('should query pending SMS', () async { ... });
    test('should query failed SMS', () async { ... });
    test('should delete old delivered SMS', () async { ... });
    test('should handle concurrent inserts', () async { ... });
    test('should maintain referential integrity', () async { ... });
  });
}
```

**Validation:**
- [ ] All unit tests pass
- [ ] Code coverage >80%
- [ ] No race conditions

---

## ✅ Acceptance Criteria

**Must meet ALL criteria:**

1. ✅ SQLite database successfully created
2. ✅ All CRUD operations functional
3. ✅ Existing history migrated without data loss
4. ✅ SMS listener uses database instead of SharedPreferences
5. ✅ Unit tests pass with >80% coverage
6. ✅ Data persists across app restart
7. ✅ UI displays history correctly
8. ✅ No performance regression

---

## 🧪 Testing Plan

### Unit Tests
- Database initialization
- CRUD operations
- Migration logic
- Concurrent access

### Integration Tests
- Send SMS → verify stored in database
- Restart app → verify data persists
- Query history → verify UI displays correctly

### Manual Testing
1. Fresh install → send SMS → check database
2. Upgrade from old version → verify migration
3. Send 10 SMS rapidly → verify all stored
4. Restart app → verify history intact

---

## 🚨 Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Migration data loss | High | Low | Keep backup in SharedPreferences |
| Database corruption | High | Low | Add database integrity checks |
| Performance degradation | Medium | Low | Add indexes, optimize queries |
| Disk space issues | Medium | Low | Implement retention policy |

---

## 📊 Success Metrics

- ✅ Zero data loss during migration
- ✅ Database operations <10ms for inserts
- ✅ Database operations <50ms for queries
- ✅ All unit tests passing
- ✅ No crashes or errors in production

---

## 🔗 Related Documents

- Main TODO: `/docs/project-planning/02-main-todo-list.md`
- Database Schema: (this document, Task 1.2)
- Test Plan: (this document, Testing Plan section)

---

**Status:** ⏳ Pending User Approval
**Ready to Start:** Yes (no dependencies)
