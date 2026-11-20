import 'dart:async';

import '../protocol/types.dart' show Bounds;
import '../types.dart';

/// Thrown by [ExecutionerActions.dispatch] with a protocol-style error code.
class ExecutionerActionException implements Exception {
  const ExecutionerActionException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

typedef ExecutionerTapHandler = FutureOr<void> Function();
typedef ExecutionerInputHandler = FutureOr<void> Function(String text);
typedef ExecutionerScrollHandler = FutureOr<void> Function({
  String? direction,
  num? amount,
});
typedef ExecutionerValueGetter = String? Function();
typedef ExecutionerFlagGetter = bool Function();
typedef ExecutionerBoundsResolver = Bounds? Function();

const Set<String> _tapRoles = {
  'button',
  'link',
  'pressable',
  'checkbox',
  'switch',
  'tab',
};
const Set<String> _inputRoles = {
  'textbox',
  'search',
  'textinput',
  'input',
};
const Set<String> _scrollRoles = {'scrollview', 'list', 'scroll'};

/// A single addressable UI element known to the Xecutioner SDK.
///
/// Framework layers (Flutter widgets, React Native components, tests) create
/// these and hand them to [ExecutionerActions]. The registry turns them into
/// snapshot nodes and dispatches tap / input / scroll commands to the
/// registered handlers — no per-app `performAction` switch required.
class ExecutionerElement {
  ExecutionerElement({
    required this.id,
    this.role = 'view',
    this.label,
    this.labelGetter,
    this.valueGetter,
    this.sensitive = false,
    this.enabledGetter,
    this.visibleGetter,
    this.selectedGetter,
    this.checkedGetter,
    this.explicitActions,
    this.onTap,
    this.onInput,
    this.onScroll,
    this.boundsResolver,
    this.metadata = const {},
  });

  /// Stable identifier used as `elementId` in commands and snapshots.
  final String id;

  /// Accessibility-style role: button, textbox, scrollview, tab, ...
  final String role;

  /// Static label, or a live getter for dynamic labels.
  final String? label;
  final ExecutionerValueGetter? labelGetter;

  /// Live value getter (e.g. current text field content).
  final ExecutionerValueGetter? valueGetter;

  /// When true the snapshot redacts label/value automatically.
  final bool sensitive;

  final ExecutionerFlagGetter? enabledGetter;
  final ExecutionerFlagGetter? visibleGetter;
  final ExecutionerFlagGetter? selectedGetter;

  /// true / false / 'mixed' style checked state.
  final Object? Function()? checkedGetter;

  /// Explicit action list override. When null, inferred from role + handlers.
  final List<String>? explicitActions;

  final ExecutionerTapHandler? onTap;
  final ExecutionerInputHandler? onInput;
  final ExecutionerScrollHandler? onScroll;

  /// Optional framework hook to resolve on-screen bounds (e.g. via GlobalKey).
  final ExecutionerBoundsResolver? boundsResolver;

  /// Extra opaque data surfaced in the snapshot node's props.
  final Map<String, dynamic> metadata;

  String? get effectiveLabel => label ?? labelGetter?.call();
  String? get effectiveValue => valueGetter?.call();
  bool get isEnabled => enabledGetter?.call() ?? true;
  bool get isVisible => visibleGetter?.call() ?? true;
  bool? get isSelected => selectedGetter?.call();

  /// Actions this element can currently perform.
  List<String> get resolvedActions {
    final explicit = explicitActions;
    if (explicit != null) return explicit;
    final out = <String>[];
    if (onTap != null || _tapRoles.contains(role)) out.add('tap');
    if (onInput != null || _inputRoles.contains(role)) out.add('input');
    if (onScroll != null || _scrollRoles.contains(role)) out.add('scroll');
    if (out.isEmpty && role == 'view') {
      // Plain containers stay non-actionable.
      return const [];
    }
    return out;
  }

  /// Convert to the framework-free host node consumed by snapshot capture.
  HostUiNode toHostUiNode() {
    return HostUiNode(
      testID: id,
      accessibilityLabel: effectiveLabel,
      accessibilityRole: role,
      accessibilityState: AccessibilityState(
        disabled: isEnabled ? null : true,
        selected: isSelected,
        checked: checkedGetter?.call(),
      ),
      accessibilityValue: AccessibilityValue(text: effectiveValue),
      accessible: true,
      xecutionerRedact: sensitive ? true : null,
      props: {
        'value': effectiveValue,
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
      bounds: boundsResolver?.call(),
      actions: resolvedActions,
    );
  }
}

/// Registry + dispatcher for [ExecutionerElement]s.
///
/// Apps register elements once (declaratively or via framework widgets) and the
/// registry handles snapshot serialization and command dispatch for every app.
class ExecutionerActions {
  final Map<String, ExecutionerElement> _elements = {};

  /// Register or replace an element.
  ExecutionerElement add(ExecutionerElement element) {
    _elements[element.id] = element;
    return element;
  }

  void remove(String id) => _elements.remove(id);

  ExecutionerElement? operator [](String id) => _elements[id];

  bool contains(String id) => _elements.containsKey(id);

  List<ExecutionerElement> get elements =>
      List<ExecutionerElement>.unmodifiable(_elements.values);

  /// Convenience: register a tappable element.
  ExecutionerElement onTap(
    String id, {
    String role = 'button',
    String? label,
    ExecutionerValueGetter? labelGetter,
    ExecutionerValueGetter? valueGetter,
    bool sensitive = false,
    ExecutionerFlagGetter? enabledGetter,
    ExecutionerFlagGetter? visibleGetter,
    ExecutionerFlagGetter? selectedGetter,
    Object? Function()? checkedGetter,
    required ExecutionerTapHandler onTap,
    ExecutionerBoundsResolver? boundsResolver,
    Map<String, dynamic> metadata = const {},
  }) {
    return add(
      ExecutionerElement(
        id: id,
        role: role,
        label: label,
        labelGetter: labelGetter,
        valueGetter: valueGetter,
        sensitive: sensitive,
        enabledGetter: enabledGetter,
        visibleGetter: visibleGetter,
        selectedGetter: selectedGetter,
        checkedGetter: checkedGetter,
        onTap: onTap,
        boundsResolver: boundsResolver,
        metadata: metadata,
      ),
    );
  }

  /// Convenience: register an element that accepts text input.
  ///
  /// Provide [onInput] for custom handling, or [getValue]/[setValue] to bind a
  /// text controller abstraction.
  ExecutionerElement onInput(
    String id, {
    String role = 'textbox',
    String? label,
    ExecutionerValueGetter? labelGetter,
    ExecutionerValueGetter? valueGetter,
    bool sensitive = false,
    ExecutionerFlagGetter? enabledGetter,
    ExecutionerFlagGetter? visibleGetter,
    ExecutionerFlagGetter? selectedGetter,
    Object? Function()? checkedGetter,
    ExecutionerTapHandler? onTap,
    ExecutionerInputHandler? onInput,
    String? Function()? getValue,
    void Function(String text)? setValue,
    ExecutionerBoundsResolver? boundsResolver,
    Map<String, dynamic> metadata = const {},
  }) {
    return add(
      ExecutionerElement(
        id: id,
        role: role,
        label: label,
        labelGetter: labelGetter,
        valueGetter: valueGetter ?? getValue,
        sensitive: sensitive,
        enabledGetter: enabledGetter,
        visibleGetter: visibleGetter,
        selectedGetter: selectedGetter,
        checkedGetter: checkedGetter,
        onTap: onTap,
        onInput: onInput ??
            (setValue != null
                ? (String text) => setValue(text)
                : null),
        boundsResolver: boundsResolver,
        metadata: metadata,
      ),
    );
  }

  /// Convenience: register a scrollable element.
  ExecutionerElement onScroll(
    String id, {
    String role = 'scrollview',
    String? label,
    ExecutionerValueGetter? labelGetter,
    ExecutionerFlagGetter? enabledGetter,
    ExecutionerFlagGetter? visibleGetter,
    required ExecutionerScrollHandler onScroll,
    ExecutionerBoundsResolver? boundsResolver,
    Map<String, dynamic> metadata = const {},
  }) {
    return add(
      ExecutionerElement(
        id: id,
        role: role,
        label: label,
        labelGetter: labelGetter,
        enabledGetter: enabledGetter,
        visibleGetter: visibleGetter,
        onScroll: onScroll,
        boundsResolver: boundsResolver,
        metadata: metadata,
      ),
    );
  }

  ExecutionerElement? _find(String elementId) {
    final direct = _elements[elementId];
    if (direct != null) return direct;
    for (final element in _elements.values) {
      if (element.id.endsWith(':$elementId')) return element;
    }
    return null;
  }

  /// Dispatch a host action request to the registered element.
  ///
  /// Throws [ExecutionerActionException] with a protocol-style error code when
  /// the element is missing or cannot perform the requested action.
  Future<void> dispatch(PerformActionRequest request) async {
    final element = _find(request.elementId);
    if (element == null) {
      throw ExecutionerActionException(
        'element_not_found',
        'Element not found: ${request.elementId}',
      );
    }
    if (element.isVisible == false) {
      throw ExecutionerActionException(
        'not_actionable',
        'Element ${request.elementId} is not visible',
      );
    }

    switch (request.action) {
      case 'tap':
        final handler = element.onTap;
        if (handler == null) {
          throw ExecutionerActionException(
            'not_actionable',
            'Element ${request.elementId} does not support tap',
          );
        }
        await handler();
      case 'input':
        final handler = element.onInput;
        if (handler == null) {
          throw ExecutionerActionException(
            'not_actionable',
            'Element ${request.elementId} does not support input',
          );
        }
        await handler(request.text ?? '');
      case 'scroll':
        final handler = element.onScroll;
        if (handler == null) {
          throw ExecutionerActionException(
            'not_actionable',
            'Element ${request.elementId} does not support scroll',
          );
        }
        await handler(direction: request.direction, amount: request.amount);
      default:
        throw ExecutionerActionException(
          'not_actionable',
          'Unsupported action ${request.action} for ${request.elementId}',
        );
    }
  }

  /// Build host nodes for snapshot capture. Invisible elements are skipped.
  List<HostUiNode> toHostUiNodes() {
    return elements
        .where((element) => element.isVisible)
        .map((element) => element.toHostUiNode())
        .toList();
  }
}
