import '../protocol/helpers.dart';
import '../protocol/types.dart';

/// Builders for [Command]s so hosts and tests don't hand-assemble callId,
/// idempotencyKey and deadline fields.
class XecutionerCommands {
  XecutionerCommands._();

  static const int defaultTimeoutMs = 15000;

  static num _deadline({num? timeoutMs, num? deadline}) {
    if (deadline != null) return deadline;
    return DateTime.now().millisecondsSinceEpoch +
        (timeoutMs ?? defaultTimeoutMs);
  }

  static Command _base(
    String action, {
    String? callId,
    String? idempotencyKey,
    num? deadline,
    num? timeoutMs,
  }) {
    return Command(
      callId: callId ?? createCallId(),
      action: action,
      idempotencyKey: idempotencyKey ?? createIdempotencyKey(),
      deadline: _deadline(timeoutMs: timeoutMs, deadline: deadline),
    );
  }

  static Command tap(
    String elementId, {
    String? snapshotId,
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    final base = _base(
      'tap',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      snapshotId: snapshotId,
      elementId: elementId,
    );
  }

  static Command input(
    String elementId,
    String text, {
    String? snapshotId,
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    final base = _base(
      'input',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      snapshotId: snapshotId,
      elementId: elementId,
      text: text,
    );
  }

  static Command scroll(
    String elementId, {
    String? direction,
    num? amount,
    String? snapshotId,
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    final base = _base(
      'scroll',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      snapshotId: snapshotId,
      elementId: elementId,
      direction: direction,
      amount: amount,
    );
  }

  static Command navigate(
    String screenId, {
    Map<String, dynamic>? params,
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    final base = _base(
      'navigate',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      screenId: screenId,
      params: params,
    );
  }

  static Command back({
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    return _base(
      'back',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
  }

  static Command readScreen({
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    return _base(
      'read_screen',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
  }

  static Command getContext({
    num? maxDestinations,
    String? callId,
    String? idempotencyKey,
    num? timeoutMs,
  }) {
    final base = _base(
      'get_context',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      maxDestinations: maxDestinations,
    );
  }

  static Command waitFor({
    String? elementId,
    String? labelContains,
    num? timeoutMs,
    String? callId,
    String? idempotencyKey,
  }) {
    final base = _base(
      'wait_for',
      callId: callId,
      idempotencyKey: idempotencyKey,
      timeoutMs: timeoutMs,
    );
    return Command(
      callId: base.callId,
      action: base.action,
      idempotencyKey: base.idempotencyKey,
      deadline: base.deadline,
      waitCondition: WaitCondition(
        elementId: elementId,
        labelContains: labelContains,
        timeoutMs: timeoutMs,
      ),
    );
  }
}
