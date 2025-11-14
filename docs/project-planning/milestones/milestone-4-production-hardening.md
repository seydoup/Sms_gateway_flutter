# Milestone 4: Production Hardening

**Status:** ⏳ Pending
**Priority:** MEDIUM
**Estimated Effort:** 3-4 hours
**Dependencies:** Milestone 3 ✅
**Start Date:** TBD
**Completion Date:** TBD

---

## 🎯 Objective

Harden the application for high-volume production use with concurrency controls, guaranteed background processing, health monitoring, and intelligent error handling.

---

## 🎁 Deliverables

1. ✅ Thread-safe database operations
2. ✅ WorkManager for reliable background processing
3. ✅ Health monitoring dashboard
4. ✅ Intelligent error categorization
5. ✅ Load testing validation (100+ SMS)
6. ✅ Production deployment readiness

---

## 📋 Detailed Tasks

### Task 4.1: SMS Handler Synchronization (45 min)

**Files to Modify:**
- `pubspec.yaml`

**Dependencies:**
```yaml
dependencies:
  synchronized: ^3.1.0
```

**Files to Modify:**
- `lib/services/sms_queue_database.dart`
- `lib/services/sms_listeneing.dart`

**Implementation:**

```dart
import 'package:synchronized/synchronized.dart';

class SmsQueueDatabase {
  // ... existing code ...

  final Lock _writeLock = Lock();

  Future<int> insertSms(QueuedSms sms) async {
    return await _writeLock.synchronized(() async {
      final db = await database;
      return await db.insert('sms_queue', sms.toMap());
    });
  }

  Future<int> updateSmsStatus(
    int id,
    SmsStatus status, {
    String? errorMessage,
    int? httpStatusCode,
    DateTime? nextRetryAt,
  }) async {
    return await _writeLock.synchronized(() async {
      final db = await database;
      return await db.update(
        'sms_queue',
        {
          'status': status.toString(),
          if (errorMessage != null) 'error_message': errorMessage,
          if (httpStatusCode != null) 'http_status_code': httpStatusCode,
          if (nextRetryAt != null) 'next_retry_at': nextRetryAt.toIso8601String(),
          'retry_count': 'retry_count + 1',
          'last_attempt_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // Protect all write operations with lock
  Future<int> deleteSms(int id) async {
    return await _writeLock.synchronized(() async {
      final db = await database;
      return await db.delete('sms_queue', where: 'id = ?', whereArgs: [id]);
    });
  }
}
```

**Validation:**
- [ ] Concurrent writes don't corrupt database
- [ ] Lock prevents race conditions
- [ ] Performance acceptable (<50ms lock wait)

---

### Task 4.2: Background Task Reliability (90 min)

**Files to Modify:**
- `pubspec.yaml`

**Dependencies:**
```yaml
dependencies:
  workmanager: ^0.5.2
```

**Files to Create:**
- `lib/services/background_worker.dart`

**Implementation:**

```dart
import 'package:workmanager/workmanager.dart';

const String retryQueueTask = 'retryQueueProcessor';

// Top-level function for WorkManager callback
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case retryQueueTask:
        await _processRetryQueue();
        return true;
      default:
        return false;
    }
  });
}

Future<void> _processRetryQueue() async {
  try {
    // Initialize services
    await PreferencesService.init();
    final db = SmsQueueDatabase.instance;
    final network = NetworkMonitor.instance;
    await network.initialize();

    // Check network
    if (!await network.isConnected()) {
      print('[BackgroundWorker] No network, skipping retry queue');
      return;
    }

    // Process retry queue
    final retryManager = RetryManager.instance;
    await retryManager.processRetryQueue();

    print('[BackgroundWorker] Retry queue processed successfully');
  } catch (e, stackTrace) {
    print('[BackgroundWorker] Error processing retry queue: $e');
    print(stackTrace);
  }
}

class BackgroundWorkerService {
  static final BackgroundWorkerService instance = BackgroundWorkerService._init();

  BackgroundWorkerService._init();

  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: false,
    );

    // Register periodic task (runs every 15 minutes)
    await Workmanager().registerPeriodicTask(
      '1', // Unique task ID
      retryQueueTask,
      frequency: Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: Duration(minutes: 1),
    );
  }

  Future<void> triggerImmediateRetry() async {
    await Workmanager().registerOneOffTask(
      DateTime.now().millisecondsSinceEpoch.toString(),
      retryQueueTask,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  }

  Future<void> cancelAll() async {
    await Workmanager().cancelAll();
  }
}
```

**Android Configuration:**

Update `android/app/src/main/AndroidManifest.xml`:
```xml
<!-- Add inside <application> tag -->
<provider
    android:name="androidx.work.impl.WorkManagerInitializer"
    android:authorities="${applicationId}.workmanager-init"
    android:exported="false"
    tools:node="remove" />
```

**App Initialization:**

Update `lib/main.dart`:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize background worker
  await BackgroundWorkerService.instance.initialize();

  runApp(MyApp());
}
```

**Validation:**
- [ ] Background task runs every 15 minutes
- [ ] Task runs when app is killed
- [ ] Task respects network constraints
- [ ] Immediate trigger works

---

### Task 4.3: Health Dashboard (60 min)

**Files to Create:**
- `lib/pages/health_dashboard.dart`
- `lib/widgets/health_metric_card.dart`
- `lib/services/health_metrics.dart`

**Health Metrics Service:**

```dart
class HealthMetrics {
  final int queueSize;
  final int pendingMessages;
  final int failedMessages;
  final double successRate24h;
  final String? lastError;
  final DateTime? lastErrorTime;
  final NetworkStatus networkStatus;
  final bool isRetryProcessorRunning;
  final int totalMessagesToday;
  final int deliveredMessagesToday;

  HealthMetrics({
    required this.queueSize,
    required this.pendingMessages,
    required this.failedMessages,
    required this.successRate24h,
    this.lastError,
    this.lastErrorTime,
    required this.networkStatus,
    required this.isRetryProcessorRunning,
    required this.totalMessagesToday,
    required this.deliveredMessagesToday,
  });
}

class HealthMetricsService {
  static final HealthMetricsService instance = HealthMetricsService._init();

  HealthMetricsService._init();

  Future<HealthMetrics> getMetrics() async {
    final db = SmsQueueDatabase.instance;
    final network = NetworkMonitor.instance;

    // Get queue size
    final queueSize = await db.getQueueSize();

    // Get pending and failed counts
    final pendingSms = await db.getPendingSms();
    final failedSms = await db.getFailedSms();

    // Calculate success rate (last 24 hours)
    final twentyFourHoursAgo = DateTime.now().subtract(Duration(hours: 24));
    final recentSms = await db.getSmsAfter(twentyFourHoursAgo);
    final delivered = recentSms.where((s) => s.status == SmsStatus.delivered).length;
    final successRate = recentSms.isEmpty ? 100.0 : (delivered / recentSms.length) * 100;

    // Get last error
    final errorLogs = await ErrorLogger.instance.getRecentErrors(limit: 1);
    final lastError = errorLogs.isNotEmpty ? errorLogs.first : null;

    // Get today's stats
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final todaySms = await db.getSmsAfter(startOfDay);
    final todayDelivered = todaySms.where((s) => s.status == SmsStatus.delivered).length;

    return HealthMetrics(
      queueSize: queueSize,
      pendingMessages: pendingSms.length,
      failedMessages: failedSms.length,
      successRate24h: successRate,
      lastError: lastError?.message,
      lastErrorTime: lastError?.timestamp,
      networkStatus: network.currentStatus,
      isRetryProcessorRunning: RetryManager.instance.isProcessing,
      totalMessagesToday: todaySms.length,
      deliveredMessagesToday: todayDelivered,
    );
  }
}
```

**Health Dashboard UI:**

```dart
class HealthDashboardPage extends StatefulWidget {
  @override
  _HealthDashboardPageState createState() => _HealthDashboardPageState();
}

class _HealthDashboardPageState extends State<HealthDashboardPage> {
  HealthMetrics? _metrics;
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(Duration(seconds: 10), (_) => _loadMetrics());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    final metrics = await HealthMetricsService.instance.getMetrics();
    if (mounted) {
      setState(() {
        _metrics = metrics;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('System Health'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMetrics,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMetrics,
              child: ListView(
                padding: EdgeInsets.all(16),
                children: [
                  // Overall Status
                  _buildStatusCard(),
                  SizedBox(height: 16),

                  // Queue Metrics
                  Row(
                    children: [
                      Expanded(child: HealthMetricCard(
                        title: 'Queue Size',
                        value: '${_metrics!.queueSize}',
                        icon: Icons.queue,
                        color: _metrics!.queueSize > 100 ? Colors.orange : Colors.blue,
                      )),
                      SizedBox(width: 16),
                      Expanded(child: HealthMetricCard(
                        title: 'Pending',
                        value: '${_metrics!.pendingMessages}',
                        icon: Icons.schedule,
                        color: Colors.orange,
                      )),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Success Metrics
                  Row(
                    children: [
                      Expanded(child: HealthMetricCard(
                        title: 'Success Rate (24h)',
                        value: '${_metrics!.successRate24h.toStringAsFixed(1)}%',
                        icon: Icons.check_circle,
                        color: _metrics!.successRate24h >= 95 ? Colors.green : Colors.red,
                      )),
                      SizedBox(width: 16),
                      Expanded(child: HealthMetricCard(
                        title: 'Failed',
                        value: '${_metrics!.failedMessages}',
                        icon: Icons.error,
                        color: _metrics!.failedMessages > 0 ? Colors.red : Colors.green,
                      )),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Today's Stats
                  Row(
                    children: [
                      Expanded(child: HealthMetricCard(
                        title: 'Today Total',
                        value: '${_metrics!.totalMessagesToday}',
                        icon: Icons.today,
                        color: Colors.blue,
                      )),
                      SizedBox(width: 16),
                      Expanded(child: HealthMetricCard(
                        title: 'Today Delivered',
                        value: '${_metrics!.deliveredMessagesToday}',
                        icon: Icons.check,
                        color: Colors.green,
                      )),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Network Status
                  _buildNetworkCard(),
                  SizedBox(height: 16),

                  // Last Error
                  if (_metrics!.lastError != null)
                    _buildLastErrorCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    final isHealthy = _metrics!.successRate24h >= 95 &&
                     _metrics!.failedMessages < 10 &&
                     _metrics!.networkStatus == NetworkStatus.connected;

    return Card(
      color: isHealthy ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isHealthy ? Icons.check_circle : Icons.warning,
              color: isHealthy ? Colors.green : Colors.red,
              size: 48,
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isHealthy ? 'System Healthy' : 'System Issues Detected',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isHealthy ? Colors.green[900] : Colors.red[900],
                    ),
                  ),
                  Text(
                    isHealthy
                        ? 'All systems operating normally'
                        : 'Check metrics below for details',
                    style: TextStyle(
                      color: isHealthy ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkCard() {
    final isConnected = _metrics!.networkStatus == NetworkStatus.connected;
    return Card(
      child: ListTile(
        leading: Icon(
          isConnected ? Icons.wifi : Icons.wifi_off,
          color: isConnected ? Colors.green : Colors.red,
        ),
        title: Text('Network Status'),
        subtitle: Text(
          isConnected ? 'Connected' : 'Disconnected',
          style: TextStyle(
            color: isConnected ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: _metrics!.isRetryProcessorRunning
            ? Chip(label: Text('Retry Active'), backgroundColor: Colors.orange[100])
            : null,
      ),
    );
  }

  Widget _buildLastErrorCard() {
    return Card(
      color: Colors.red[50],
      child: ListTile(
        leading: Icon(Icons.error, color: Colors.red),
        title: Text('Last Error'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _metrics!.lastError!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 4),
            Text(
              _formatTimeSince(_metrics!.lastErrorTime!),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeSince(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
    if (diff.inDays < 1) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
```

**Health Metric Card Widget:**

```dart
class HealthMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const HealthMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 36),
            SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

**Validation:**
- [ ] Dashboard displays accurate metrics
- [ ] Auto-refresh works
- [ ] Manual refresh works
- [ ] Status colors accurate

---

### Task 4.4: Error Categorization (30 min)

**Files to Create:**
- `lib/services/error_classifier.dart`

**Implementation:**

```dart
class ErrorClassifier {
  static ErrorCategory categorize(dynamic error, {int? httpStatusCode}) {
    // HTTP errors
    if (httpStatusCode != null) {
      if (httpStatusCode >= 400 && httpStatusCode < 500) {
        return ErrorCategory.http;
      }
      if (httpStatusCode >= 500) {
        return ErrorCategory.http;
      }
    }

    // Network errors
    if (error is SocketException) {
      return ErrorCategory.network;
    }
    if (error is TimeoutException) {
      return ErrorCategory.network;
    }
    if (error is HandshakeException) {
      return ErrorCategory.network;
    }

    // Database errors
    if (error is DatabaseException) {
      return ErrorCategory.database;
    }

    // Permission errors
    if (error.toString().contains('permission')) {
      return ErrorCategory.permissions;
    }

    // Configuration errors
    if (error is FormatException || error is ArgumentError) {
      return ErrorCategory.configuration;
    }

    return ErrorCategory.unknown;
  }

  static Duration getRetryDelayForCategory(ErrorCategory category, int attemptNumber) {
    switch (category) {
      case ErrorCategory.network:
        // Network errors: aggressive retry (might come back quickly)
        return Duration(seconds: 5 * attemptNumber);

      case ErrorCategory.http:
        // HTTP errors: moderate retry (server issues)
        return Duration(seconds: 30 * attemptNumber);

      case ErrorCategory.configuration:
        // Configuration errors: no point retrying quickly
        return Duration(minutes: 30);

      case ErrorCategory.permissions:
        // Permission errors: no point retrying
        return Duration(hours: 1);

      case ErrorCategory.database:
        // Database errors: retry after a moment
        return Duration(seconds: 10);

      default:
        // Unknown: use default exponential backoff
        return Duration(seconds: 15 * attemptNumber);
    }
  }

  static bool shouldRetry(ErrorCategory category) {
    switch (category) {
      case ErrorCategory.network:
      case ErrorCategory.http:
      case ErrorCategory.database:
        return true; // These can be transient

      case ErrorCategory.configuration:
      case ErrorCategory.permissions:
        return false; // These need manual intervention

      default:
        return true; // When in doubt, retry
    }
  }
}
```

**Update RetryManager to use categorization:**

```dart
Future<void> _scheduleNextRetry(QueuedSms sms, {dynamic error, String? errorMessage}) async {
  final category = ErrorClassifier.categorize(error, httpStatusCode: sms.httpStatusCode);

  if (!ErrorClassifier.shouldRetry(category)) {
    await _db.updateSmsStatus(
      sms.id!,
      SmsStatus.failed,
      errorMessage: 'Error type does not warrant retry: ${category.toString()}',
    );
    return;
  }

  final nextDelay = ErrorClassifier.getRetryDelayForCategory(category, sms.retryCount);
  final nextRetryAt = DateTime.now().add(nextDelay);

  await _db.updateSmsStatus(
    sms.id!,
    SmsStatus.retrying,
    errorMessage: errorMessage ?? error?.toString(),
    nextRetryAt: nextRetryAt,
  );

  // Log with category
  await ErrorLogger.instance.logError(
    category: category,
    message: errorMessage ?? error?.toString() ?? 'Unknown error',
    smsId: sms.id,
  );
}
```

**Validation:**
- [ ] Errors categorized correctly
- [ ] Retry delays appropriate per category
- [ ] Non-retryable errors marked as failed

---

### Task 4.5: Load Testing (45 min)

**Files to Create:**
- `test/load_test/sms_burst_test.dart`

**Load Test Script:**

```dart
import 'package:test/test.dart';
import 'package:sms_gateway/services/sms_queue_database.dart';
import 'package:sms_gateway/models/queued_sms.dart';

void main() {
  group('Load Testing', () {
    test('should handle 100 concurrent SMS without data loss', () async {
      final db = SmsQueueDatabase.instance;

      // Clear database
      await db.deleteAll();

      // Generate 100 SMS
      final futures = List.generate(100, (i) async {
        final sms = QueuedSms(
          sender: '+155500${i.toString().padLeft(5, '0')}',
          content: 'Load test message #$i',
          timestamp: DateTime.now().toIso8601String(),
          createdAt: DateTime.now(),
          status: SmsStatus.pending,
          retryCount: 0,
        );

        return await db.insertSms(sms);
      });

      // Insert all in parallel
      final ids = await Future.wait(futures);

      // Verify all inserted
      expect(ids.length, 100);
      expect(ids.every((id) => id > 0), true);

      // Verify no data loss
      final allSms = await db.getPendingSms();
      expect(allSms.length, 100);

      // Verify database integrity
      final uniqueSenders = allSms.map((s) => s.sender).toSet();
      expect(uniqueSenders.length, 100);
    }, timeout: Timeout(Duration(minutes: 2)));

    test('should handle rapid status updates without corruption', () async {
      final db = SmsQueueDatabase.instance;

      // Create SMS
      final sms = QueuedSms(
        sender: '+1234567890',
        content: 'Test message',
        timestamp: DateTime.now().toIso8601String(),
        createdAt: DateTime.now(),
        status: SmsStatus.pending,
        retryCount: 0,
      );

      final id = await db.insertSms(sms);

      // Update status 50 times concurrently
      final futures = List.generate(50, (i) async {
        await db.updateSmsStatus(
          id,
          i % 2 == 0 ? SmsStatus.retrying : SmsStatus.inProgress,
        );
      });

      await Future.wait(futures);

      // Verify database not corrupted
      final retrieved = await db.getSmsById(id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, id);
    });
  });
}
```

**Manual Load Testing:**

1. Use ADB to send 100 SMS rapidly:
```bash
for i in {1..100}; do
  adb emu sms send "+155500000$i" "Load test message $i"
  sleep 0.1
done
```

2. Monitor:
   - Database integrity
   - Memory usage
   - UI responsiveness
   - CPU usage

**Validation:**
- [ ] 100 SMS handled without data loss
- [ ] No database corruption
- [ ] UI remains responsive
- [ ] Memory usage acceptable (<200MB)

---

## ✅ Acceptance Criteria

**Must meet ALL criteria:**

1. ✅ No data loss under concurrent load (100+ SMS)
2. ✅ Background processing works when app killed
3. ✅ Health dashboard provides accurate real-time metrics
4. ✅ Error categorization improves retry logic
5. ✅ Load test passes without crashes
6. ✅ Database operations thread-safe
7. ✅ Memory usage acceptable under load
8. ✅ All tests passing

---

## 🧪 Testing Plan

### Unit Tests
- Lock synchronization
- Error categorization
- Health metrics calculation

### Integration Tests
- Background worker execution
- WorkManager task scheduling

### Load Tests
- 100 concurrent SMS inserts
- Rapid status updates
- Extended operation (24h stress test)

### Manual Testing

**Test 1: Background Reliability**
1. Send test SMS
2. Force-close app (swipe away)
3. Wait 2 minutes
4. Send SMS to device via another phone
5. Check logs - verify SMS received and queued
6. Wait 15 minutes
7. Verify background worker processed queue

**Test 2: Concurrent Burst**
1. Use ADB script to send 100 SMS in 10 seconds
2. Monitor health dashboard
3. Verify all 100 SMS appear in queue
4. Verify no duplicates
5. Verify no missing messages
6. Check database integrity

**Test 3: Health Dashboard Accuracy**
1. Send 10 SMS (configure 50% success rate)
2. Check dashboard metrics match actual state
3. Verify auto-refresh updates metrics
4. Verify manual refresh works

---

## 🚨 Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| WorkManager not executing | High | Low | Add fallback foreground service |
| Lock causing deadlocks | High | Low | Use timeout on lock acquisition |
| Load test revealing memory leak | High | Medium | Profile and fix before production |
| Battery optimization killing background tasks | Medium | Medium | Guide users to disable for app |

---

## 📊 Success Metrics

- ✅ Zero data loss in load test (100 SMS)
- ✅ Background worker executes reliably (>95% success rate)
- ✅ Health dashboard updates in real-time
- ✅ Error categorization reduces unnecessary retries
- ✅ Memory usage <200MB under load
- ✅ All tests passing

---

## 🚀 Production Deployment Checklist

After completing Milestone 4:

- [ ] All 4 milestones completed
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Load test passed (100+ SMS)
- [ ] 24-hour stress test completed
- [ ] Memory profiling shows no leaks
- [ ] Battery usage acceptable
- [ ] Error handling comprehensive
- [ ] Documentation updated
- [ ] User guide created
- [ ] Server endpoints configured
- [ ] Monitoring dashboard accessible
- [ ] Backup and recovery tested
- [ ] Rollback plan documented

---

## 🔗 Related Documents

- Main TODO: `/docs/project-planning/02-main-todo-list.md`
- Milestone 3: `/docs/project-planning/milestones/milestone-3-delivery-tracking.md`
- Production Checklist: (this document, above)

---

**Status:** ⏳ Pending Milestone 3 Completion
**Ready to Start:** After Milestone 3 ✅
