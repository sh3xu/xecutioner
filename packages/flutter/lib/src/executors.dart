import 'dart:convert';

import 'navigation/context_reader.dart';
import 'navigation/types.dart';
import 'protocol/helpers.dart';
import 'protocol/types.dart';
import 'snapshot.dart';
import 'types.dart';

class ExecuteContext {
  ExecuteContext({
    required this.hooks,
    required Snapshot? lastSnapshot,
    required this.setLastSnapshot,
  }) : _lastSnapshot = lastSnapshot;

  final HostHooks hooks;
  Snapshot? _lastSnapshot;
  final void Function(Snapshot snapshot) setLastSnapshot;

  Snapshot? get lastSnapshot => _lastSnapshot;

  void updateLastSnapshot(Snapshot snapshot) {
    _lastSnapshot = snapshot;
    setLastSnapshot(snapshot);
  }
}

AppContextReader? _resolveContextReader(HostHooks hooks) {
  if (hooks.contextReader != null) {
    return hooks.contextReader;
  }
  if (hooks.navigation != null) {
    return createAppContextReader(
      CreateAppContextReaderOptions(
        app: const AppInfo(name: 'app', description: 'Host application'),
        navigation: hooks.navigation,
      ),
    );
  }
  return null;
}

Snapshot _readFreshSnapshot(ExecuteContext ctx, {num? tokenBudget}) {
  final reader = _resolveContextReader(ctx.hooks);
  final nav = reader?.read();
  final meta = ctx.hooks.getScreenMeta?.call();
  final root = ctx.hooks.getRootNode();
  final snapshot = captureSnapshot(
    root,
    options: SerializeOptions(
      screen: nav?.current.screenId ?? meta?.screen,
      route: meta?.route ?? nav?.current.screenId,
      tokenBudget: tokenBudget,
    ),
  );
  ctx.updateLastSnapshot(snapshot);
  return snapshot;
}

CommandResult? _assertSnapshotFresh(Command command, Snapshot? lastSnapshot) {
  if (command.snapshotId == null) {
    return null;
  }
  if (lastSnapshot == null || lastSnapshot.snapshotId != command.snapshotId) {
    return buildCommandResult(
      command.callId,
      options: BuildResultOptions(
        errorCode: 'stale_snapshot',
        errorMessage: 'snapshotId does not match the latest client snapshot',
        snapshot: lastSnapshot,
      ),
    );
  }
  return null;
}

HostUiNode? _findInTree(HostUiNode? root, String elementId) {
  if (root == null) return null;
  final stack = <HostUiNode>[root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    final id = node.testID ??
        (node.props?['testID'] is String ? node.props!['testID'] as String : null);
    if (id == elementId) {
      return node;
    }
    if (node.children != null) {
      stack.addAll(node.children!);
    }
  }
  return null;
}

AppContext? _readContext(ExecuteContext ctx, {num? maxDestinations}) {
  final reader = _resolveContextReader(ctx.hooks);
  if (reader == null) return null;
  return reader.read(maxDestinations: maxDestinations);
}

/// Execute a single UI command against the host tree / navigation adapter.
Future<CommandResult> executeCommand(
  Command command,
  ExecuteContext ctx,
) async {
  ctx.hooks.onAiActing?.call(true);
  try {
    if (command.action == 'get_context') {
      final appContext = _readContext(
        ctx,
        maxDestinations: command.maxDestinations,
      );
      if (appContext == null) {
        return buildCommandResult(
          command.callId,
          options: const BuildResultOptions(
            errorCode: 'navigation_unavailable',
            errorMessage:
                'No contextReader or navigation adapter configured on the client',
          ),
        );
      }
      final snapshot = _readFreshSnapshot(ctx);
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(snapshot: snapshot, appContext: appContext),
      );
    }

    if (command.action == 'navigate' || command.action == 'back') {
      final reader = _resolveContextReader(ctx.hooks);
      final navigation = reader?.getNavigation() ?? ctx.hooks.navigation;
      if (navigation == null) {
        return buildCommandResult(
          command.callId,
          options: const BuildResultOptions(
            errorCode: 'navigation_unavailable',
            errorMessage: 'No navigation adapter configured on the client',
          ),
        );
      }

      if (command.action == 'navigate') {
        final screenId = command.screenId;
        if (screenId == null) {
          return buildCommandResult(
            command.callId,
            options: const BuildResultOptions(
              errorCode: 'invalid_arguments',
              errorMessage: 'screenId is required for navigate',
            ),
          );
        }

        final appContext = reader?.read();
        final known =
            appContext?.destinations.any((d) => d.id == screenId) ?? false;
        final autoKnown =
            navigation.getKnownRoutes?.call().contains(screenId) ?? false;
        if (appContext != null && !known && !autoKnown) {
          return buildCommandResult(
            command.callId,
            options: BuildResultOptions(
              errorCode: 'unknown_screen',
              errorMessage: 'Unknown screenId: $screenId',
              appContext: appContext,
            ),
          );
        }

        ScreenDestination? destination;
        if (appContext != null) {
          for (final d in appContext.destinations) {
            if (d.id == screenId) {
              destination = d;
              break;
            }
          }
        }
        if (destination?.policy == 'deny') {
          return buildCommandResult(
            command.callId,
            options: BuildResultOptions(
              errorCode: 'blocked_by_policy',
              errorMessage: 'Screen $screenId is denied by screen map policy',
              appContext: appContext,
            ),
          );
        }

        if (ctx.hooks.onApprovalRequest != null &&
            destination?.policy == 'approval') {
          final approved = await ctx.hooks.onApprovalRequest!(
            ApprovalRequest(
              callId: command.callId,
              action: 'navigate',
              screenId: screenId,
            ),
          );
          if (!approved) {
            return buildCommandResult(
              command.callId,
              options: BuildResultOptions(
                errorCode: 'blocked_by_policy',
                errorMessage: 'Host denied navigation approval',
                appContext: appContext,
              ),
            );
          }
        }

        await navigation.navigate(screenId, command.params);
      } else {
        await navigation.back();
      }

      final snapshot = _readFreshSnapshot(ctx);
      final nextContext = _readContext(ctx);
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(snapshot: snapshot, appContext: nextContext),
      );
    }

    if (command.action == 'read_screen') {
      final snapshot = _readFreshSnapshot(ctx);
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(snapshot: snapshot),
      );
    }

    final stale = _assertSnapshotFresh(command, ctx.lastSnapshot);
    if (stale != null) {
      return stale;
    }

    if (command.action == 'wait_for') {
      final timeoutMs = command.waitCondition?.timeoutMs?.toInt() ?? 5000;
      final started = DateTime.now().millisecondsSinceEpoch;
      while (DateTime.now().millisecondsSinceEpoch - started < timeoutMs) {
        final snapshot = _readFreshSnapshot(ctx);
        final elementId = command.waitCondition?.elementId;
        final labelContains = command.waitCondition?.labelContains;
        if (elementId != null &&
            findElementById(snapshot.elements, elementId) != null) {
          return buildCommandResult(
            command.callId,
            options: BuildResultOptions(snapshot: snapshot),
          );
        }
        if (labelContains != null &&
            jsonEncode(snapshot.elements.map((e) => e.toJson()).toList())
                .contains(labelContains)) {
          return buildCommandResult(
            command.callId,
            options: BuildResultOptions(snapshot: snapshot),
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(
          errorCode: 'timeout',
          errorMessage: 'wait_for condition not met',
          snapshot: ctx.lastSnapshot,
        ),
      );
    }

    final elementId = command.elementId;
    if (elementId == null) {
      return buildCommandResult(
        command.callId,
        options: const BuildResultOptions(
          errorCode: 'invalid_arguments',
          errorMessage: 'elementId is required',
        ),
      );
    }

    final snapshot = ctx.lastSnapshot ?? _readFreshSnapshot(ctx);
    final element = findElementById(
      snapshot.elements,
      elementId,
      options: const FindElementOptions(allowSuffixMatch: true),
    );
    if (element == null) {
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(
          errorCode: 'element_not_found',
          errorMessage: 'Element not found: $elementId',
          snapshot: snapshot,
        ),
      );
    }

    if ((command.action == 'tap' ||
            command.action == 'scroll' ||
            command.action == 'input') &&
        !isElementActionable(element, command.action)) {
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(
          errorCode: 'not_actionable',
          errorMessage:
              'Element $elementId is not actionable for ${command.action}',
          snapshot: snapshot,
        ),
      );
    }

    if (ctx.hooks.onApprovalRequest != null) {
      final approved = await ctx.hooks.onApprovalRequest!(
        ApprovalRequest(
          callId: command.callId,
          action: command.action,
          elementId: elementId,
        ),
      );
      if (!approved) {
        return buildCommandResult(
          command.callId,
          options: BuildResultOptions(
            errorCode: 'blocked_by_policy',
            errorMessage: 'Host denied approval',
            snapshot: snapshot,
          ),
        );
      }
    }

    final root = ctx.hooks.getRootNode();
    final hostNode = _findInTree(root, elementId);
    if (hostNode == null && ctx.hooks.performAction == null) {
      return buildCommandResult(
        command.callId,
        options: BuildResultOptions(
          errorCode: 'element_not_found',
          errorMessage: 'Host node not found: $elementId',
          snapshot: snapshot,
        ),
      );
    }

    if (ctx.hooks.performAction != null) {
      await ctx.hooks.performAction!(
        PerformActionRequest(
          action: command.action,
          elementId: elementId,
          text: command.text,
          direction: command.direction,
          amount: command.amount,
        ),
      );
    } else if (command.action == 'input' && hostNode != null) {
      hostNode.props = {...?hostNode.props, 'value': command.text ?? ''};
      if (hostNode.accessibilityValue != null) {
        hostNode.accessibilityValue =
            AccessibilityValue(text: command.text ?? '');
      }
    }

    final next = _readFreshSnapshot(ctx);
    return buildCommandResult(
      command.callId,
      options: BuildResultOptions(snapshot: next),
    );
  } catch (error) {
    final message = error.toString();
    final errorCode = message.contains('navigation_unavailable')
        ? 'navigation_unavailable'
        : 'internal_error';
    return buildCommandResult(
      command.callId,
      options: BuildResultOptions(
        errorCode: errorCode,
        errorMessage: message,
        snapshot: ctx.lastSnapshot,
      ),
    );
  } finally {
    ctx.hooks.onAiActing?.call(false);
  }
}
