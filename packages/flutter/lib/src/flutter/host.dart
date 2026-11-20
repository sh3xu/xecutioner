import 'package:flutter/material.dart';

import '../sdk/executioner.dart';
import 'inspector.dart';

/// Drop-in wrapper that optionally overlays the debug inspector over [child].
///
/// ```dart
/// runApp(XecutionerHost(
///   executioner: xecutioner,
///   showInspector: kDebugMode,
///   child: MaterialApp(...),
/// ));
/// ```
class XecutionerHost extends StatelessWidget {
  const XecutionerHost({
    super.key,
    required this.executioner,
    required this.child,
    this.showInspector = false,
  });

  final Xecutioner executioner;
  final Widget child;

  /// Show the floating debug inspector (intended for debug builds).
  final bool showInspector;

  @override
  Widget build(BuildContext context) {
    if (!showInspector) {
      return child;
    }
    return Stack(
      children: [
        child,
        Positioned(
          right: 16,
          bottom: 16,
          child: XecutionerInspector(executioner: executioner),
        ),
      ],
    );
  }
}
