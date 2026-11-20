import 'navigation/types.dart';
import 'protocol/types.dart';

/// Host-provided node shape. Apps can feed Semantics / Key trees.
/// Keeps the client free of Flutter runtime coupling for unit tests.
class HostUiNode {
  HostUiNode({
    this.testID,
    this.accessibilityLabel,
    this.accessibilityRole,
    this.accessibilityState,
    this.accessibilityValue,
    this.accessible,
    this.xecutionerRedact,
    this.props,
    this.children,
    this.bounds,
    this.actions,
  });

  String? testID;
  String? accessibilityLabel;
  String? accessibilityRole;
  AccessibilityState? accessibilityState;
  AccessibilityValue? accessibilityValue;
  bool? accessible;

  /// NOTE: Mark sensitive fields for redaction in snapshots.
  bool? xecutionerRedact;
  Map<String, dynamic>? props;
  List<HostUiNode>? children;
  Bounds? bounds;
  List<String>? actions;
}

class AccessibilityState {
  AccessibilityState({this.disabled, this.selected, this.checked});

  bool? disabled;
  bool? selected;

  /// true / false / "mixed"
  Object? checked;
}

class AccessibilityValue {
  AccessibilityValue({this.text});

  String? text;
}

class SnapshotContext {
  const SnapshotContext({this.screen, this.route, this.tokenBudget});

  final String? screen;
  final String? route;
  final num? tokenBudget;
}

class PerformActionRequest {
  const PerformActionRequest({
    required this.action,
    required this.elementId,
    this.text,
    this.direction,
    this.amount,
  });

  final String action;
  final String elementId;
  final String? text;
  final String? direction;
  final num? amount;
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.callId,
    required this.action,
    this.elementId,
    this.screenId,
  });

  final String callId;
  final String action;
  final String? elementId;
  final String? screenId;
}

class ScreenMeta {
  const ScreenMeta({this.screen, this.route});

  final String? screen;
  final String? route;
}

typedef OnAiActing = void Function(bool acting);
typedef OnApprovalRequest = Future<bool> Function(ApprovalRequest payload);
typedef GetRootNode = HostUiNode? Function();
typedef PerformAction = Future<void> Function(PerformActionRequest request);
typedef GetScreenMeta = ScreenMeta Function();

class HostHooks {
  HostHooks({
    required this.getRootNode,
    this.onAiActing,
    this.onApprovalRequest,
    this.performAction,
    this.getScreenMeta,
    this.contextReader,
    this.navigation,
  });

  final OnAiActing? onAiActing;
  final OnApprovalRequest? onApprovalRequest;
  final GetRootNode getRootNode;
  final PerformAction? performAction;
  final GetScreenMeta? getScreenMeta;

  /// Preferred: full context reader (runtime + declared + auto routes).
  final AppContextReader? contextReader;

  /// Optional bare navigation adapter when no contextReader is provided.
  final NavigationAdapter? navigation;
}
