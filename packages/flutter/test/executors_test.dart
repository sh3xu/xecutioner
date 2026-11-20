import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

HostUiNode makeTree() {
  return HostUiNode(
    testID: 'root',
    children: [
      HostUiNode(
        testID: 'buy',
        accessibilityRole: 'button',
        accessibilityLabel: 'Buy',
      ),
      HostUiNode(
        testID: 'email',
        accessibilityRole: 'textbox',
        accessibilityLabel: 'Email',
        props: {'value': ''},
      ),
    ],
  );
}

void main() {
  group('executeCommand', () {
    test('reads the screen', () async {
      final root = makeTree();
      Snapshot? last;
      final result = await executeCommand(
        Command(
          callId: 'c1',
          action: 'read_screen',
          idempotencyKey: 'i1',
          deadline: DateTime.now().millisecondsSinceEpoch + 5000,
        ),
        ExecuteContext(
          hooks: HostHooks(
            getRootNode: () => root,
            getScreenMeta: () => const ScreenMeta(screen: 'Home'),
          ),
          lastSnapshot: null,
          setLastSnapshot: (s) => last = s,
        ),
      );
      expect(result.ok, isTrue);
      expect(result.snapshot?.screen, 'Home');
      expect(last?.snapshotId, result.snapshot?.snapshotId);
    });

    test('taps an element via performAction', () async {
      final root = makeTree();
      final taps = <String>[];
      Snapshot? lastSnapshot;

      final read = await executeCommand(
        Command(
          callId: 'r1',
          action: 'read_screen',
          idempotencyKey: 'ir',
          deadline: DateTime.now().millisecondsSinceEpoch + 5000,
        ),
        ExecuteContext(
          hooks: HostHooks(getRootNode: () => root),
          lastSnapshot: null,
          setLastSnapshot: (s) => lastSnapshot = s,
        ),
      );
      expect(read.ok, isTrue);
      expect(lastSnapshot, isNotNull);
      final snapshotId = lastSnapshot!.snapshotId;

      final result = await executeCommand(
        Command(
          callId: 'c2',
          action: 'tap',
          elementId: 'buy',
          snapshotId: snapshotId,
          idempotencyKey: 'i2',
          deadline: DateTime.now().millisecondsSinceEpoch + 5000,
        ),
        ExecuteContext(
          hooks: HostHooks(
            getRootNode: () => root,
            performAction: (request) async {
              taps.add(request.elementId);
            },
          ),
          lastSnapshot: lastSnapshot,
          setLastSnapshot: (s) => lastSnapshot = s,
        ),
      );

      expect(result.ok, isTrue);
      expect(taps, ['buy']);
    });

    test('rejects stale snapshots', () async {
      final root = makeTree();
      final result = await executeCommand(
        Command(
          callId: 'c3',
          action: 'tap',
          elementId: 'buy',
          snapshotId: 'old',
          idempotencyKey: 'i3',
          deadline: DateTime.now().millisecondsSinceEpoch + 5000,
        ),
        ExecuteContext(
          hooks: HostHooks(getRootNode: () => root),
          lastSnapshot: Snapshot(
            snapshotId: 'new',
            capturedAt: DateTime.now().millisecondsSinceEpoch,
            elements: const [],
          ),
          setLastSnapshot: (_) {},
        ),
      );
      expect(result.ok, isFalse);
      expect(result.errorCode, 'stale_snapshot');
    });
  });
}
