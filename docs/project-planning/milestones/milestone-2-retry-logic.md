# Milestone 2: Retry Logic

**Status:** ⏳ Pending
**Priority:** MUST HAVE
**Estimated Effort:** 3-4 hours
**Dependencies:** Milestone 1 ✅
**Start Date:** TBD
**Completion Date:** TBD

---

## 🎯 Objective

Implement intelligent retry logic with exponential backoff and network-aware queuing to ensure no message loss during temporary network or server failures.

---

## 🎁 Deliverables

1. ✅ Network status monitoring service
2. ✅ Retry manager with exponential backoff
3. ✅ Background queue processor
4. ✅ Network-aware SMS sending
5. ✅ UI indicators for retry status
6. ✅ Integration tests for retry scenarios

---

## 📋 Detailed Tasks

### Task 2.1: Add Network Monitoring (30 min)

**Files to Modify:**
- `pubspec.yaml`

**Dependencies:**
```yaml
dependencies:
  connectivity_plus: ^5.0.2
```

**Files to Create:**
- `lib/services/network_monitor.dart`

**Implementation:**
```dart
class NetworkMonitor {
  static final NetworkMonitor instance = NetworkMonitor._init();
  final Connectivity _connectivity = Connectivity();

  StreamController<NetworkStatus> _statusController = StreamController.broadcast();
  Stream<NetworkStatus> get statusStream => _statusController.stream;

  NetworkStatus _currentStatus = NetworkStatus.unknown;
  NetworkStatus get currentStatus => _currentStatus;

  Future<void> initialize() async {
    // Check initial connectivity
    _currentStatus = await _checkConnectivity();

    // Listen for changes
    _connectivity.onConnectivityChanged.listen((result) async {
      final newStatus = _mapConnectivityResult(result);
      if (newStatus != _currentStatus) {
        _currentStatus = newStatus;
        _statusController.add(newStatus);
      }
    });
  }

  Future<NetworkStatus> _checkConnectivity() async { ... }
  Future<bool> isConnected() async { ... }
  void dispose() { ... }
}

enum NetworkStatus {
  connected,
  disconnected,
  unknown
}
```

**Validation:**
- [ ] Network status detected correctly
- [ ] Status changes trigger events
- [ ] Works on WiFi and mobile data

---

### Task 2.2: Create Retry Manager (60 min)

**Files to Create:**
- `lib/models/retry_config.dart`
- `lib/services/retry_manager.dart`

**Retry Configuration:**
```dart
class RetryConfig {
  final int maxRetries;
  final List<Duration> retryDelays;
  final Duration maxRetryWindow;

  const RetryConfig({
    this.maxRetries = 5,
    this.retryDelays = const [
      Duration(seconds: 5),    // 1st retry
      Duration(seconds: 15),   // 2nd retry
      Duration(minutes: 1),    // 3rd retry
      Duration(minutes: 5),    // 4th retry
      Duration(minutes: 15),   // 5th retry
    ],
    this.maxRetryWindow = const Duration(hours: 24),
  });

  Duration getDelayForAttempt(int attemptNumber) {
    if (attemptNumber >= retryDelays.length) {
      return retryDelays.last;
    }
    return retryDelays[attemptNumber];
  }
}
```

**Retry Manager:**
```dart
class RetryManager {
  static final RetryManager instance = RetryManager._init();
  final SmsQueueDatabase _db = SmsQueueDatabase.instance;
  final NetworkMonitor _network = NetworkMonitor.instance;
  final RetryConfig config = RetryConfig();

  Timer? _retryTimer;
  bool _isProcessing = false;

  void startProcessing() {
    // Start periodic check for retry queue
    _retryTimer = Timer.periodic(Duration(seconds: 30), (_) {
      processRetryQueue();
    });

    // Also process when network becomes available
    _network.statusStream.listen((status) {
      if (status == NetworkStatus.connected) {
        processRetryQueue();
      }
    });
  }

  Future<void> processRetryQueue() async {
    if (_isProcessing) return;
    if (!await _network.isConnected()) return;

    _isProcessing = true;
    try {
      final pendingSms = await _db.getSmsForRetry();

      for (var sms in pendingSms) {
        await _retrySms(sms);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _retrySms(QueuedSms sms) async {
    // Check if max retries exceeded
    if (sms.retryCount >= config.maxRetries) {
      await _db.updateSmsStatus(
        sms.id!,
        SmsStatus.failed,
        errorMessage: 'Max retries exceeded',
      );
      return;
    }

    // Check if retry window expired
    if (sms.createdAt.add(config.maxRetryWindow).isBefore(DateTime.now())) {
      await _db.updateSmsStatus(
        sms.id!,
        SmsStatus.failed,
        errorMessage: 'Retry window expired',
      );
      return;
    }

    // Attempt retry
    await _db.updateSmsStatus(sms.id!, SmsStatus.inProgress);

    try {
      final success = await _attemptSend(sms);

      if (success) {
        await _db.updateSmsStatus(sms.id!, SmsStatus.delivered);
      } else {
        await _scheduleNextRetry(sms);
      }
    } catch (e) {
      await _scheduleNextRetry(sms, errorMessage: e.toString());
    }
  }

  Future<void> _scheduleNextRetry(QueuedSms sms, {String? errorMessage}) async {
    final nextDelay = config.getDelayForAttempt(sms.retryCount);
    final nextRetryAt = DateTime.now().add(nextDelay);

    await _db.updateSmsStatus(
      sms.id!,
      SmsStatus.retrying,
      errorMessage: errorMessage,
      nextRetryAt: nextRetryAt,
    );
  }

  Future<bool> _attemptSend(QueuedSms sms) async { ... }

  void stopProcessing() {
    _retryTimer?.cancel();
  }
}
```

**Validation:**
- [ ] Retry delays follow exponential backoff
- [ ] Max retries enforced
- [ ] Network status checked before retry

---

### Task 2.3: Update SMS Listener (45 min)

**Files to Modify:**
- `lib/services/sms_listeneing.dart`

**Changes:**

```dart
class SmsListenerService {
  final NetworkMonitor _network = NetworkMonitor.instance;
  final RetryManager _retry = RetryManager.instance;

  Future<void> _processSmsMessage(SmsMessage message) async {
    final queuedSms = QueuedSms(
      sender: message.address ?? 'Unknown',
      content: message.body ?? '',
      timestamp: DateTime.now().toIso8601String(),
      createdAt: DateTime.now(),
      status: SmsStatus.pending,
      retryCount: 0,
    );

    final db = SmsQueueDatabase.instance;
    final smsId = await db.insertSms(queuedSms);

    // Check network before attempting send
    if (!await _network.isConnected()) {
      print('No network connection. SMS queued for later delivery.');
      return; // Will be picked up by retry manager
    }

    // Attempt immediate send
    await db.updateSmsStatus(smsId, SmsStatus.inProgress);

    try {
      final success = await _sendToAllEndpoints(queuedSms.copyWith(id: smsId));

      if (success) {
        await db.updateSmsStatus(smsId, SmsStatus.delivered);
      } else {
        // Schedule for retry
        final nextRetryAt = DateTime.now().add(Duration(seconds: 5));
        await db.updateSmsStatus(
          smsId,
          SmsStatus.retrying,
          nextRetryAt: nextRetryAt,
        );
      }
    } catch (e) {
      // Queue for retry on error
      final nextRetryAt = DateTime.now().add(Duration(seconds: 5));
      await db.updateSmsStatus(
        smsId,
        SmsStatus.retrying,
        errorMessage: e.toString(),
        nextRetryAt: nextRetryAt,
      );
    }
  }

  Future<bool> _sendToAllEndpoints(QueuedSms sms) async {
    final endpoints = await _loadActiveEndpoints();
    if (endpoints.isEmpty) return false;

    final results = <EndpointResult>[];

    for (var endpoint in endpoints) {
      try {
        final success = await _sendSmsToEndpoint(sms, endpoint);
        results.add(EndpointResult(
          endpointName: endpoint.name,
          endpointUrl: endpoint.url,
          status: success ? 'success' : 'failed',
          method: endpoint.method,
        ));
      } catch (e) {
        results.add(EndpointResult(
          endpointName: endpoint.name,
          endpointUrl: endpoint.url,
          status: 'error',
          method: endpoint.method,
        ));
      }
    }

    // Save results to database
    await SmsQueueDatabase.instance.updateEndpointResults(sms.id!, results);

    // Return true only if ALL endpoints succeeded
    return results.every((r) => r.status == 'success');
  }
}
```

**Validation:**
- [ ] Network checked before send
- [ ] Failed sends queued for retry
- [ ] Successful sends marked as delivered

---

### Task 2.4: Add Retry UI Indicators (30 min)

**Files to Modify:**
- `lib/pages/sms_history_page.dart`
- `lib/widgets/history_item_card.dart` (if exists, or create)

**UI Updates:**

```dart
class HistoryItemCard extends StatelessWidget {
  final QueuedSms sms;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _buildStatusIcon(),
        title: Text('From: ${sms.sender}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sms.content, maxLines: 2, overflow: TextOverflow.ellipsis),
            SizedBox(height: 4),
            _buildStatusText(),
          ],
        ),
        trailing: _buildRetryInfo(),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (sms.status) {
      case SmsStatus.delivered:
        return Icon(Icons.check_circle, color: Colors.green);
      case SmsStatus.retrying:
        return Icon(Icons.sync, color: Colors.orange);
      case SmsStatus.failed:
        return Icon(Icons.error, color: Colors.red);
      case SmsStatus.inProgress:
        return CircularProgressIndicator();
      default:
        return Icon(Icons.schedule, color: Colors.grey);
    }
  }

  Widget _buildStatusText() {
    switch (sms.status) {
      case SmsStatus.delivered:
        return Text('Delivered', style: TextStyle(color: Colors.green));
      case SmsStatus.retrying:
        return Text('Retrying (${sms.retryCount}/${RetryConfig().maxRetries})',
            style: TextStyle(color: Colors.orange));
      case SmsStatus.failed:
        return Text('Failed: ${sms.errorMessage}',
            style: TextStyle(color: Colors.red));
      default:
        return Text('Pending', style: TextStyle(color: Colors.grey));
    }
  }

  Widget? _buildRetryInfo() {
    if (sms.status == SmsStatus.retrying && sms.nextRetryAt != null) {
      final timeUntil = sms.nextRetryAt!.difference(DateTime.now());
      if (timeUntil.isNegative) {
        return Text('Retrying soon...');
      }
      return Text('Retry in ${_formatDuration(timeUntil)}');
    }
    return null;
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}
```

**Validation:**
- [ ] Status icons display correctly
- [ ] Retry count shown
- [ ] Next retry time displayed
- [ ] Color coding clear and intuitive

---

### Task 2.5: Integration & Testing (60 min)

**Files to Create:**
- `test/services/retry_manager_test.dart`
- `test/integration/retry_flow_test.dart`

**Unit Tests:**
```dart
void main() {
  group('RetryManager', () {
    test('should calculate exponential backoff correctly', () { ... });
    test('should respect max retries', () { ... });
    test('should not retry when offline', () { ... });
    test('should process queue when network restored', () { ... });
    test('should expire old messages', () { ... });
  });

  group('NetworkMonitor', () {
    test('should detect network changes', () { ... });
    test('should emit status events', () { ... });
  });
}
```

**Integration Tests:**
```dart
void main() {
  testWidgets('Offline to online retry flow', (tester) async {
    // 1. Start app
    // 2. Disable network
    // 3. Send SMS
    // 4. Verify queued with status "pending"
    // 5. Enable network
    // 6. Wait for retry
    // 7. Verify status changed to "delivered"
  });
}
```

**Validation:**
- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Manual testing confirms retry behavior

---

## ✅ Acceptance Criteria

**Must meet ALL criteria:**

1. ✅ Network status accurately detected
2. ✅ SMS queued when network unavailable
3. ✅ Automatic retry with exponential backoff
4. ✅ Network restoration triggers retry
5. ✅ Max retries enforced
6. ✅ UI shows retry status accurately
7. ✅ No message loss during network outages
8. ✅ All tests passing

---

## 🧪 Testing Plan

### Unit Tests
- Retry delay calculation
- Max retry enforcement
- Network detection
- Queue processing logic

### Integration Tests
- Offline → send → online → verify delivery
- Multiple failures → exponential backoff
- Max retries → mark as failed

### Manual Testing Scenarios

**Test 1: Offline Queuing**
1. Turn off WiFi and mobile data
2. Send test SMS to device
3. Verify SMS queued with "pending" status
4. Turn on WiFi
5. Verify automatic retry within 5 seconds
6. Verify status changes to "delivered"

**Test 2: Exponential Backoff**
1. Configure endpoint to always fail (unreachable URL)
2. Send test SMS
3. Observe retry timing in logs:
   - Attempt 1: immediate
   - Attempt 2: +5s
   - Attempt 3: +15s
   - Attempt 4: +60s
   - Attempt 5: +300s
4. Verify UI shows increasing retry delays

**Test 3: Max Retries**
1. Configure endpoint to always fail
2. Send test SMS
3. Wait for all retries to complete
4. Verify status changes to "failed"
5. Verify error message: "Max retries exceeded"

**Test 4: Network Flapping**
1. Send SMS
2. Quickly toggle network on/off several times
3. Verify only one retry attempt at a time
4. Verify eventual delivery when network stable

---

## 🚨 Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Retry storm on network restore | Medium | Medium | Rate limit retry processing |
| Battery drain from retry timer | Medium | Low | Use efficient polling interval (30s) |
| Network detection false positives | Low | Medium | Verify connectivity with actual request |
| Retry queue grows unbounded | High | Low | Enforce max retry window (24h) |

---

## 📊 Success Metrics

- ✅ 100% message delivery when network restored within 24h
- ✅ Retry delays match exponential backoff schedule
- ✅ No duplicate sends to endpoints
- ✅ Battery usage <5% increase
- ✅ All tests passing

---

## 🔗 Related Documents

- Main TODO: `/docs/project-planning/02-main-todo-list.md`
- Milestone 1: `/docs/project-planning/milestones/milestone-1-database-foundation.md`
- Retry Configuration: (this document, Task 2.2)

---

**Status:** ⏳ Pending Milestone 1 Completion
**Ready to Start:** After Milestone 1 ✅
