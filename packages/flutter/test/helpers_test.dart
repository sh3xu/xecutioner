import 'package:test/test.dart';
import 'package:xecutioner_flutter/xecutioner_flutter.dart';

void main() {
  group('protocol helpers', () {
    test('findElementById walks children', () {
      final el = findElementById(
        const [
          UiElement(
            id: 'root',
            role: 'view',
            children: [
              UiElement(id: 'buy', role: 'button', label: 'Buy'),
            ],
          ),
        ],
        'buy',
      );
      expect(el?.label, 'Buy');
    });

    test('mergeDestinations prefers declared', () {
      final merged = mergeDestinations(
        auto: const [
          ScreenDestination(
            id: 'orders',
            title: 'orders',
            description: 'auto',
            source: 'auto',
          ),
        ],
        declared: const [
          ScreenDestination(
            id: 'orders',
            title: 'Orders',
            description: 'List of orders',
            source: 'declared',
          ),
        ],
      );
      expect(merged.single.title, 'Orders');
      expect(merged.single.source, 'declared');
    });

    test('isElementActionable respects actions and role', () {
      expect(
        isElementActionable(
          const UiElement(id: 'a', role: 'button'),
          'tap',
        ),
        isTrue,
      );
      expect(
        isElementActionable(
          const UiElement(
            id: 'b',
            role: 'view',
            actions: ['scroll'],
          ),
          'tap',
        ),
        isFalse,
      );
    });

    test('validateCommand rejects unknown actions', () {
      final result = validateCommand({
        'callId': 'c1',
        'action': 'explode',
        'idempotencyKey': 'i1',
        'deadline': 1,
      });
      expect(result.ok, isFalse);
    });
  });
}
