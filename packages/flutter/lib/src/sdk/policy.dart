/// Client-side policy decisions for element actions and screen navigation.
enum XecutionerPolicyDecision { allow, approval, deny }

/// Glob-style pattern matcher: `*` matches any sequence, `?` one character.
/// Patterns are matched against the whole value (case-sensitive).
bool xecutionerPatternMatches(String pattern, String value) {
  if (pattern == value) return true;
  if (!pattern.contains('*') && !pattern.contains('?')) return false;

  final regex = StringBuffer('^');
  for (final ch in pattern.split('')) {
    if (ch == '*') {
      regex.write('.*');
    } else if (ch == '?') {
      regex.write('.');
    } else {
      regex.write(RegExp.escape(ch));
    }
  }
  regex.write(r'$');
  return RegExp(regex.toString()).hasMatch(value);
}

/// Declarative allow / approval / deny / redact rules evaluated on the client.
///
/// Keeps per-app policy code at zero: apps declare patterns once and the
/// [Xecutioner] facade enforces them before commands reach handlers.
class XecutionerPolicy {
  const XecutionerPolicy({
    this.approvalElementPatterns = const [],
    this.denyElementPatterns = const [],
    this.redactElementPatterns = const [],
    this.approvalScreens = const [],
    this.denyScreens = const [],
  });

  /// Element ids requiring user approval before tap/input/scroll.
  final List<String> approvalElementPatterns;

  /// Element ids that must never be actuated.
  final List<String> denyElementPatterns;

  /// Element ids whose snapshot label/value must be redacted.
  final List<String> redactElementPatterns;

  /// Screen ids requiring approval before navigation.
  final List<String> approvalScreens;

  /// Screen ids that must never be navigated to.
  final List<String> denyScreens;

  static const XecutionerPolicy permissive = XecutionerPolicy();

  bool _anyMatch(List<String> patterns, String value) {
    for (final pattern in patterns) {
      if (xecutionerPatternMatches(pattern, value)) return true;
    }
    return false;
  }

  /// Decision for an element action. Deny wins over approval.
  XecutionerPolicyDecision checkElement(String elementId) {
    if (_anyMatch(denyElementPatterns, elementId)) {
      return XecutionerPolicyDecision.deny;
    }
    if (_anyMatch(approvalElementPatterns, elementId)) {
      return XecutionerPolicyDecision.approval;
    }
    return XecutionerPolicyDecision.allow;
  }

  /// Decision for navigating to a screen.
  XecutionerPolicyDecision checkScreen(String screenId) {
    if (_anyMatch(denyScreens, screenId)) {
      return XecutionerPolicyDecision.deny;
    }
    if (_anyMatch(approvalScreens, screenId)) {
      return XecutionerPolicyDecision.approval;
    }
    return XecutionerPolicyDecision.allow;
  }

  /// Whether snapshot output for this element must be redacted.
  bool shouldRedact(String elementId) =>
      _anyMatch(redactElementPatterns, elementId);
}
