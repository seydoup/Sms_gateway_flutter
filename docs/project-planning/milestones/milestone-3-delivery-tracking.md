# Milestone 3: Delivery Tracking

**Status:** ⏳ Pending
**Priority:** HIGH
**Estimated Effort:** 2-3 hours
**Dependencies:** Milestone 2 ✅
**Start Date:** TBD
**Completion Date:** TBD

---

## 🎯 Objective

Implement comprehensive delivery tracking with user notifications, manual retry interface, asynchronous endpoint processing, and structured error logging for production visibility and control.

---

## 🎁 Deliverables

1. ✅ Enhanced delivery status tracking per endpoint
2. ✅ Push notifications for delivery failures
3. ✅ Failed messages UI with manual retry
4. ✅ Asynchronous parallel endpoint processing
5. ✅ Structured error logging system
6. ✅ Error log viewer interface

---

## 📋 Detailed Tasks

### Task 3.1: Enhanced Status Tracking (30 min)

**Files to Modify:**
- `lib/services/sms_queue_database.dart` (schema update)

**Database Migration:**
```sql
-- Add detailed tracking fields (already in Milestone 1 schema)
-- Ensure per-endpoint tracking in endpoint_results JSON

-- Update database version
-- Add migration for existing data
```

**Files to Modify:**
- `lib/models/queued_sms.dart`
- `lib/models/endpoint_result.dart`

**Enhanced Endpoint Result:**
```dart
class EndpointResult {
  final String endpointName;
  final String endpointUrl;
  final String method;
  final EndpointStatus status;
  final int? httpStatusCode;
  final String? errorMessage;
  final DateTime attemptedAt;
  final Duration? responseTime;

  EndpointResult({
    required this.endpointName,
    required this.endpointUrl,
    required this.method,
    required this.status,
    this.httpStatusCode,
    this.errorMessage,
    required this.attemptedAt,
    this.responseTime,
  });

  Map<String, dynamic> toJson() { ... }
  factory EndpointResult.fromJson(Map<String, dynamic> json) { ... }
}

enum EndpointStatus {
  success,
  httpError,
  networkError,
  timeout,
  unknown
}
```

**Validation:**
- [ ] Schema updated successfully
- [ ] Existing data migrated
- [ ] Per-endpoint status tracked

---

### Task 3.2: Implement Notifications (45 min)

**Files to Modify:**
- `pubspec.yaml`

**Dependencies:**
```yaml
dependencies:
  flutter_local_notifications: ^17.0.0
```

**Files to Create:**
- `lib/services/notification_service.dart`

**Implementation:**
```dart
class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  NotificationService._init();

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channel
    const channel = AndroidNotificationChannel(
      'sms_delivery_failures',
      'SMS Delivery Failures',
      description: 'Notifications for failed SMS deliveries',
      importance: Importance.high,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> notifyDeliveryFailed({
    required int smsId,
    required String sender,
    required int failedEndpoints,
    required int totalEndpoints,
  }) async {
    await _notifications.show(
      smsId,
      'SMS Delivery Failed',
      'Failed to deliver message from $sender to $failedEndpoints/$totalEndpoints endpoints',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sms_delivery_failures',
          'SMS Delivery Failures',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: 'failed_sms:$smsId',
    );
  }

  Future<void> notifyAllRetriesExhausted({
    required int smsId,
    required String sender,
  }) async {
    await _notifications.show(
      smsId + 1000000, // Offset to avoid ID collision
      'SMS Permanently Failed',
      'Message from $sender failed after all retry attempts',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'sms_delivery_failures',
          'SMS Delivery Failures',
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          color: Color(0xFFFF0000),
        ),
      ),
      payload: 'failed_sms:$smsId',
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload?.startsWith('failed_sms:') ?? false) {
      final smsId = int.parse(response.payload!.split(':')[1]);
      // Navigate to failed messages page
      // This will be handled by the app's navigation system
    }
  }
}
```

**Android Configuration:**
- Update `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**Validation:**
- [ ] Notifications appear on failure
- [ ] Notification tap navigates to failed messages
- [ ] Different notification types work

---

### Task 3.3: Asynchronous Endpoint Processing (30 min)

**Files to Modify:**
- `lib/services/sms_listeneing.dart`

**Current (Sequential):**
```dart
for (var endpoint in endpoints) {
  final result = await _sendSmsToEndpoint(sms, endpoint);
  results.add(result);
}
```

**New (Parallel):**
```dart
Future<List<EndpointResult>> _sendToAllEndpoints(QueuedSms sms) async {
  final endpoints = await _loadActiveEndpoints();
  if (endpoints.isEmpty) return [];

  // Send to all endpoints in parallel
  final futures = endpoints.map((endpoint) =>
    _sendSmsToEndpointWithTiming(sms, endpoint)
  ).toList();

  // Wait for all to complete
  final results = await Future.wait(
    futures,
    eagerError: false, // Don't stop on first error
  );

  return results;
}

Future<EndpointResult> _sendSmsToEndpointWithTiming(
  QueuedSms sms,
  Endpoint endpoint,
) async {
  final stopwatch = Stopwatch()..start();

  try {
    final success = await _sendSmsToEndpoint(sms, endpoint)
        .timeout(Duration(seconds: 30));

    stopwatch.stop();

    return EndpointResult(
      endpointName: endpoint.name,
      endpointUrl: endpoint.url,
      method: endpoint.method,
      status: success ? EndpointStatus.success : EndpointStatus.httpError,
      attemptedAt: DateTime.now(),
      responseTime: stopwatch.elapsed,
    );
  } on TimeoutException {
    stopwatch.stop();
    return EndpointResult(
      endpointName: endpoint.name,
      endpointUrl: endpoint.url,
      method: endpoint.method,
      status: EndpointStatus.timeout,
      errorMessage: 'Request timed out after 30 seconds',
      attemptedAt: DateTime.now(),
      responseTime: stopwatch.elapsed,
    );
  } catch (e) {
    stopwatch.stop();
    return EndpointResult(
      endpointName: endpoint.name,
      endpointUrl: endpoint.url,
      method: endpoint.method,
      status: EndpointStatus.networkError,
      errorMessage: e.toString(),
      attemptedAt: DateTime.now(),
      responseTime: stopwatch.elapsed,
    );
  }
}
```

**Validation:**
- [ ] All endpoints processed in parallel
- [ ] Total time ≈ slowest endpoint (not sum)
- [ ] One endpoint failure doesn't block others

---

### Task 3.4: Create Failed Messages UI (45 min)

**Files to Create:**
- `lib/pages/failed_messages_page.dart`
- `lib/widgets/failed_message_card.dart`

**Failed Messages Page:**
```dart
class FailedMessagesPage extends StatefulWidget {
  @override
  _FailedMessagesPageState createState() => _FailedMessagesPageState();
}

class _FailedMessagesPageState extends State<FailedMessagesPage> {
  List<QueuedSms> _failedMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFailedMessages();
  }

  Future<void> _loadFailedMessages() async {
    setState(() => _isLoading = true);
    final messages = await SmsQueueDatabase.instance.getFailedSms();
    setState(() {
      _failedMessages = messages;
      _isLoading = false;
    });
  }

  Future<void> _retryMessage(QueuedSms sms) async {
    // Reset retry count and schedule for immediate retry
    await SmsQueueDatabase.instance.updateSmsStatus(
      sms.id!,
      SmsStatus.pending,
      nextRetryAt: DateTime.now(),
    );

    // Trigger retry manager
    await RetryManager.instance.processRetryQueue();

    // Reload list
    await _loadFailedMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Retry scheduled for message from ${sms.sender}')),
    );
  }

  Future<void> _retryAll() async {
    for (var sms in _failedMessages) {
      await SmsQueueDatabase.instance.updateSmsStatus(
        sms.id!,
        SmsStatus.pending,
        nextRetryAt: DateTime.now(),
      );
    }

    await RetryManager.instance.processRetryQueue();
    await _loadFailedMessages();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Retrying ${_failedMessages.length} messages')),
    );
  }

  Future<void> _deleteMessage(QueuedSms sms) async {
    await SmsQueueDatabase.instance.deleteSms(sms.id!);
    await _loadFailedMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Failed Messages'),
        actions: [
          if (_failedMessages.isNotEmpty)
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: _retryAll,
              tooltip: 'Retry All',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _failedMessages.isEmpty
              ? Center(child: Text('No failed messages'))
              : ListView.builder(
                  itemCount: _failedMessages.length,
                  itemBuilder: (context, index) {
                    return FailedMessageCard(
                      sms: _failedMessages[index],
                      onRetry: () => _retryMessage(_failedMessages[index]),
                      onDelete: () => _deleteMessage(_failedMessages[index]),
                    );
                  },
                ),
    );
  }
}
```

**Failed Message Card:**
```dart
class FailedMessageCard extends StatelessWidget {
  final QueuedSms sms;
  final VoidCallback onRetry;
  final VoidCallback onDelete;

  const FailedMessageCard({
    required this.sms,
    required this.onRetry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8),
      child: ExpansionTile(
        leading: Icon(Icons.error, color: Colors.red),
        title: Text('From: ${sms.sender}'),
        subtitle: Text(
          '${sms.content.substring(0, min(50, sms.content.length))}...\n'
          'Failed: ${_formatDate(sms.createdAt)} | Retries: ${sms.retryCount}',
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Error: ${sms.errorMessage ?? "Unknown error"}',
                    style: TextStyle(color: Colors.red)),
                SizedBox(height: 8),
                if (sms.endpointResults != null)
                  ..._buildEndpointResults(),
                SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: Icon(Icons.delete),
                      label: Text('Delete'),
                      onPressed: onDelete,
                    ),
                    SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: Icon(Icons.refresh),
                      label: Text('Retry Now'),
                      onPressed: onRetry,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildEndpointResults() {
    return sms.endpointResults!.map((result) {
      return ListTile(
        leading: Icon(
          result.status == EndpointStatus.success
              ? Icons.check_circle
              : Icons.error,
          color: result.status == EndpointStatus.success
              ? Colors.green
              : Colors.red,
        ),
        title: Text(result.endpointName),
        subtitle: Text(
          result.status == EndpointStatus.success
              ? 'Delivered (${result.responseTime?.inMilliseconds}ms)'
              : 'Failed: ${result.errorMessage}',
        ),
      );
    }).toList();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
```

**Navigation Update:**
- Add route to failed messages page in main router
- Add link from main dashboard/history page

**Validation:**
- [ ] Failed messages page displays correctly
- [ ] Manual retry button works
- [ ] Retry all button works
- [ ] Delete button works
- [ ] Endpoint details shown

---

### Task 3.5: Structured Error Logging (30 min)

**Files to Create:**
- `lib/models/error_log_entry.dart`
- `lib/services/error_logger.dart`

**Error Log Entry:**
```dart
class ErrorLogEntry {
  final int? id;
  final DateTime timestamp;
  final ErrorCategory category;
  final String message;
  final String? stackTrace;
  final Map<String, dynamic>? context;
  final int? smsId;

  ErrorLogEntry({
    this.id,
    required this.timestamp,
    required this.category,
    required this.message,
    this.stackTrace,
    this.context,
    this.smsId,
  });

  Map<String, dynamic> toMap() { ... }
  factory ErrorLogEntry.fromMap(Map<String, dynamic> map) { ... }
}

enum ErrorCategory {
  network,
  http,
  database,
  permissions,
  configuration,
  unknown
}
```

**Error Logger:**
```dart
class ErrorLogger {
  static final ErrorLogger instance = ErrorLogger._init();
  final SmsQueueDatabase _db = SmsQueueDatabase.instance;

  ErrorLogger._init();

  Future<void> logError({
    required ErrorCategory category,
    required String message,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
    int? smsId,
  }) async {
    final entry = ErrorLogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      stackTrace: stackTrace?.toString(),
      context: context,
      smsId: smsId,
    );

    await _db.insertErrorLog(entry);

    // Also print to console in debug mode
    print('[ERROR] [$category] $message');
    if (stackTrace != null) {
      print(stackTrace);
    }
  }

  Future<List<ErrorLogEntry>> getRecentErrors({int limit = 100}) async {
    return await _db.getErrorLogs(limit: limit);
  }

  Future<void> clearOldLogs({int keepLast = 1000}) async {
    await _db.deleteOldErrorLogs(keepLast);
  }
}
```

**Update all error handlers to use ErrorLogger:**
```dart
// Example in SMS listener
try {
  await _sendSmsToEndpoint(...);
} catch (e, stackTrace) {
  await ErrorLogger.instance.logError(
    category: ErrorCategory.network,
    message: 'Failed to send SMS to endpoint: $e',
    stackTrace: stackTrace,
    context: {
      'endpoint': endpoint.url,
      'method': endpoint.method,
      'sender': sms.sender,
    },
    smsId: sms.id,
  );
}
```

**Validation:**
- [ ] Errors logged to database
- [ ] Stack traces captured
- [ ] Context information saved
- [ ] Old logs cleaned up

---

## ✅ Acceptance Criteria

**Must meet ALL criteria:**

1. ✅ Notifications sent on delivery failure
2. ✅ Failed messages accessible in dedicated UI
3. ✅ Manual retry works correctly
4. ✅ Retry all works correctly
5. ✅ Parallel processing speeds up multi-endpoint delivery
6. ✅ Detailed error logs available
7. ✅ Per-endpoint status tracked
8. ✅ All tests passing

---

## 🧪 Testing Plan

### Unit Tests
- Parallel endpoint processing
- Notification service
- Error logging

### Integration Tests
- Failed message flow
- Manual retry from UI
- Notification tap handling

### Manual Testing

**Test 1: Delivery Failure Notification**
1. Configure unreachable endpoint
2. Send test SMS
3. Verify notification appears
4. Tap notification
5. Verify navigates to failed messages page

**Test 2: Manual Retry**
1. View failed messages page
2. Click "Retry Now" on a failed message
3. Verify retry attempt occurs
4. Fix endpoint (make it reachable)
5. Retry again
6. Verify success and removal from failed list

**Test 3: Parallel Processing**
1. Configure 3 endpoints with different response times
2. Send test SMS
3. Measure total processing time
4. Verify time ≈ slowest endpoint (not sum of all)

---

## 🚨 Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Notification permission denied | Medium | Low | Request permission on app start |
| Parallel processing overwhelms server | Low | Low | Limit to reasonable number of endpoints |
| Error log grows too large | Medium | Medium | Auto-cleanup old logs (keep last 1000) |

---

## 📊 Success Metrics

- ✅ Notifications delivered within 1 second of failure
- ✅ Manual retry success rate >95%
- ✅ Parallel processing 3x faster than sequential
- ✅ Error logs provide actionable debugging info
- ✅ All tests passing

---

## 🔗 Related Documents

- Main TODO: `/docs/project-planning/02-main-todo-list.md`
- Milestone 2: `/docs/project-planning/milestones/milestone-2-retry-logic.md`

---

**Status:** ⏳ Pending Milestone 2 Completion
**Ready to Start:** After Milestone 2 ✅
