import 'protocol/helpers.dart';
import 'protocol/types.dart';
import 'types.dart';

class SerializeOptions {
  SerializeOptions({
    this.screen,
    this.route,
    this.tokenBudget,
    this.refCounter,
  });

  final String? screen;
  final String? route;
  final num? tokenBudget;

  /// NOTE: Counter for generated refs when stable ids are missing.
  RefCounter? refCounter;
}

class RefCounter {
  RefCounter({this.value = 0});

  int value;
}

String _roleOf(HostUiNode node) {
  if (node.accessibilityRole != null) {
    return node.accessibilityRole!.toLowerCase();
  }
  final propsRole = node.props?['accessibilityRole'] ?? node.props?['role'];
  if (propsRole is String) {
    return propsRole.toLowerCase();
  }
  return 'view';
}

String? _labelOf(HostUiNode node) {
  if (node.accessibilityLabel != null) return node.accessibilityLabel;
  final fromProps = node.props?['accessibilityLabel'] ?? node.props?['label'];
  return fromProps is String ? fromProps : null;
}

String? _elementValue(HostUiNode node) {
  if (node.accessibilityValue?.text != null) {
    return node.accessibilityValue!.text;
  }
  final v = node.props?['value'] ?? node.props?['placeholder'];
  return v is String ? v : null;
}

List<String> _inferActions(String role, List<String>? explicit) {
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }
  if (const ['button', 'link', 'pressable', 'checkbox', 'switch', 'tab']
      .contains(role)) {
    return const ['tap'];
  }
  if (const ['textbox', 'search', 'textinput', 'input'].contains(role)) {
    return const ['input', 'tap'];
  }
  if (const ['scrollview', 'list', 'scroll'].contains(role)) {
    return const ['scroll'];
  }
  return const [];
}

/// Convert a host UI node tree into protocol UiElements.
UiElement? serializeHostNode(HostUiNode node, {SerializeOptions? options}) {
  final counter = options?.refCounter ?? RefCounter();
  final stableId = node.testID ??
      (node.props?['testID'] is String ? node.props!['testID'] as String : null);

  final id = stableId ?? 'ref_${counter.value++}';
  final role = _roleOf(node);
  final redacted =
      node.xecutionerRedact == true || node.props?['xecutionerRedact'] == true;

  final childOptions = SerializeOptions(
    screen: options?.screen,
    route: options?.route,
    tokenBudget: options?.tokenBudget,
    refCounter: counter,
  );
  final children = (node.children ?? [])
      .map((child) => serializeHostNode(child, options: childOptions))
      .whereType<UiElement>()
      .toList();

  bool? checked;
  final rawChecked = node.accessibilityState?.checked;
  if (rawChecked == true) {
    checked = true;
  } else if (rawChecked == false) {
    checked = false;
  }

  return UiElement(
    id: id,
    role: role,
    label: redacted ? '[redacted]' : _labelOf(node),
    value: redacted ? null : _elementValue(node),
    state: ElementState(
      enabled: !(node.accessibilityState?.disabled ?? false),
      focused: false,
      checked: checked,
      visible: true,
    ),
    bounds: node.bounds,
    actions: _inferActions(role, node.actions),
    children: children.isNotEmpty ? children : null,
    redacted: redacted ? true : null,
  );
}

/// Build a protocol Snapshot from a host root node.
Snapshot captureSnapshot(HostUiNode? root, {SerializeOptions? options}) {
  final elements = <UiElement>[];
  if (root != null) {
    final serialized = serializeHostNode(root, options: options);
    if (serialized != null) {
      elements.add(serialized);
    }
  }

  final snapshot = Snapshot(
    snapshotId: createSnapshotId(),
    screen: options?.screen,
    route: options?.route,
    elements: elements,
    capturedAt: DateTime.now().millisecondsSinceEpoch,
  );

  return trimSnapshot(
    snapshot,
    options: TrimSnapshotOptions(tokenBudget: options?.tokenBudget),
  );
}
