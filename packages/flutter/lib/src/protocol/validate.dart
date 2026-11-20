import 'constants.dart';
import 'types.dart';

class ValidationResult<T> {
  const ValidationResult._({required this.ok, this.value, this.error});

  final bool ok;
  final T? value;
  final String? error;

  factory ValidationResult.success(T value) =>
      ValidationResult._(ok: true, value: value);

  factory ValidationResult.failure(String error) =>
      ValidationResult._(ok: false, error: error);
}

/// Lightweight structural validation for wire messages.
ValidationResult<Handshake> validateHandshake(
  Object? value, {
  bool strictVersion = true,
}) {
  if (value is! Map || value['type'] != 'handshake') {
    return ValidationResult.failure('Expected handshake message');
  }
  final map = Map<String, dynamic>.from(value);
  if (map['sessionId'] is! String || (map['sessionId'] as String).isEmpty) {
    return ValidationResult.failure('handshake.sessionId is required');
  }
  if (map['capabilities'] is! List) {
    return ValidationResult.failure('handshake.capabilities must be an array');
  }
  if (strictVersion && map['protocolVersion'] != protocolVersion) {
    return ValidationResult.failure(
      'Unsupported protocolVersion: ${map['protocolVersion']}',
    );
  }
  return ValidationResult.success(Handshake.fromJson(map));
}

ValidationResult<Command> validateCommand(Object? value) {
  if (value is! Map) {
    return ValidationResult.failure('Command must be an object');
  }
  final map = Map<String, dynamic>.from(value);
  const required = ['callId', 'action', 'idempotencyKey', 'deadline'];
  for (final key in required) {
    final v = map[key];
    if (v == null || v == '') {
      return ValidationResult.failure('command.$key is required');
    }
  }
  if (!commandActions.contains(map['action'].toString())) {
    return ValidationResult.failure('Unknown action: ${map['action']}');
  }
  if (map['deadline'] is! num) {
    return ValidationResult.failure('command.deadline must be a number');
  }
  return ValidationResult.success(Command.fromJson(map));
}

ValidationResult<CommandResult> validateCommandResult(Object? value) {
  if (value is! Map) {
    return ValidationResult.failure('CommandResult must be an object');
  }
  final map = Map<String, dynamic>.from(value);
  if (map['callId'] is! String || (map['callId'] as String).isEmpty) {
    return ValidationResult.failure('result.callId is required');
  }
  if (map['ok'] is! bool) {
    return ValidationResult.failure('result.ok must be a boolean');
  }
  return ValidationResult.success(CommandResult.fromJson(map));
}

ValidationResult<Snapshot> validateSnapshot(Object? value) {
  if (value is! Map) {
    return ValidationResult.failure('Snapshot must be an object');
  }
  final map = Map<String, dynamic>.from(value);
  if (map['snapshotId'] is! String || (map['snapshotId'] as String).isEmpty) {
    return ValidationResult.failure('snapshot.snapshotId is required');
  }
  if (map['elements'] is! List) {
    return ValidationResult.failure('snapshot.elements must be an array');
  }
  if (map['capturedAt'] is! num) {
    return ValidationResult.failure('snapshot.capturedAt must be a number');
  }
  return ValidationResult.success(Snapshot.fromJson(map));
}
