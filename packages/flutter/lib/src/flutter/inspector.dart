import 'dart:async';

import 'package:flutter/material.dart';

import '../protocol/types.dart';
import '../sdk/commands.dart';
import '../sdk/executioner.dart';

/// Floating debug panel for a [Xecutioner] instance: connection status, event
/// log, acting indicator, and a console that runs commands locally through the
/// same executor used for remote commands.
///
/// Normally mounted via [XecutionerHost]'s `showInspector`, but can be placed
/// anywhere inside a [Stack].
class XecutionerInspector extends StatefulWidget {
  const XecutionerInspector({super.key, required this.executioner});

  final Xecutioner executioner;

  @override
  State<XecutionerInspector> createState() => _XecutionerInspectorState();
}

class _XecutionerInspectorState extends State<XecutionerInspector> {
  static const int _maxEntries = 100;

  bool _open = false;
  bool _acting = false;
  final List<String> _entries = [];
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _logController = ScrollController();

  StreamSubscription<String>? _logSub;
  StreamSubscription<bool>? _actingSub;

  @override
  void initState() {
    super.initState();
    _logSub = widget.executioner.logs.listen((line) {
      _append(line);
    });
    _actingSub = widget.executioner.acting.listen((acting) {
      if (mounted) setState(() => _acting = acting);
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _actingSub?.cancel();
    _commandController.dispose();
    _logController.dispose();
    super.dispose();
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() {
      _entries.add(line);
      if (_entries.length > _maxEntries) {
        _entries.removeRange(0, _entries.length - _maxEntries);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logController.hasClients) {
        _logController.jumpTo(_logController.position.maxScrollExtent);
      }
    });
  }

  Command? _parseCommand(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final verb = parts.first.toLowerCase();
    String arg(int index) => parts.length > index ? parts[index] : '';
    String rest(int index) =>
        parts.length > index ? parts.sublist(index).join(' ') : '';

    switch (verb) {
      case 'tap':
        return XecutionerCommands.tap(rest(1));
      case 'input':
        return XecutionerCommands.input(arg(1), rest(2));
      case 'scroll':
        return XecutionerCommands.scroll(
          arg(1),
          direction: arg(2).isEmpty ? null : arg(2),
          amount: num.tryParse(arg(3)),
        );
      case 'navigate':
      case 'nav':
        return XecutionerCommands.navigate(rest(1));
      case 'back':
        return XecutionerCommands.back();
      case 'read':
      case 'read_screen':
        return XecutionerCommands.readScreen();
      case 'context':
      case 'get_context':
        return XecutionerCommands.getContext();
      default:
        return null;
    }
  }

  Future<void> _runCommand() async {
    final raw = _commandController.text;
    _commandController.clear();
    final command = _parseCommand(raw);
    if (command == null) {
      _append('unknown command: $raw');
      return;
    }
    _append('> ${command.action} ${command.elementId ?? command.screenId ?? ''}');
    try {
      final result = await widget.executioner.executeLocal(command);
      _append(
        result.ok
            ? 'ok ${command.action}'
            : 'error ${result.errorCode}: ${result.errorMessage}',
      );
    } catch (error) {
      _append('error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_open)
          Container(
            width: 320,
            constraints: const BoxConstraints(maxHeight: 440),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor),
              boxShadow: const [
                BoxShadow(blurRadius: 12, color: Colors.black26),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(theme),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    controller: _logController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: _entries.length,
                    itemBuilder: (context, index) => Text(
                      _entries[index],
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                const Divider(height: 1),
                _buildInput(theme),
              ],
            ),
          ),
        FloatingActionButton.small(
          heroTag: 'xecutioner-inspector',
          backgroundColor:
              _acting ? Colors.orange : theme.colorScheme.primary,
          onPressed: () => setState(() => _open = !_open),
          child: Icon(
            _open ? Icons.close : Icons.smart_button,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final connected = widget.executioner.isConnected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.hub,
            size: 16,
            color: connected ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Xecutioner • '
              '${connected ? 'connected' : 'local'}'
              '${_acting ? ' • acting' : ''}',
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInput(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commandController,
              style: theme.textTheme.bodySmall,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'tap id / input id text / navigate screen',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _runCommand(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 20),
            onPressed: _runCommand,
          ),
        ],
      ),
    );
  }
}
