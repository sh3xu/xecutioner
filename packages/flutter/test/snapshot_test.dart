import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

final tree = HostUiNode(
  testID: 'root',
  accessibilityRole: 'summary',
  children: [
    HostUiNode(
      testID: 'order-1',
      accessibilityRole: 'button',
      accessibilityLabel: 'Order 1',
    ),
    HostUiNode(
      testID: 'password',
      accessibilityRole: 'textbox',
      accessibilityLabel: 'Password',
      xecutionerRedact: true,
      accessibilityValue: AccessibilityValue(text: 'secret'),
    ),
  ],
);

void main() {
  group('serializeHostNode', () {
    test('prefers stable testIDs and redacts sensitive fields', () {
      final el = serializeHostNode(tree);
      expect(el?.id, 'root');
      expect(el?.children?[0].id, 'order-1');
      expect(el?.children?[1].label, '[redacted]');
      expect(el?.children?[1].value, isNull);
    });

    test('generates refs when testID is missing', () {
      final el = serializeHostNode(HostUiNode(accessibilityRole: 'button'));
      expect(el?.id.startsWith('ref_'), isTrue);
    });
  });

  group('captureSnapshot', () {
    test('returns a trimmed snapshot', () {
      final snap = captureSnapshot(
        tree,
        options: SerializeOptions(screen: 'Orders', tokenBudget: 500),
      );
      expect(snap.snapshotId, isNotEmpty);
      expect(snap.screen, 'Orders');
      expect(snap.elements, isNotEmpty);
    });
  });
}
