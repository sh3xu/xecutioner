/// NOTE: Wire shapes mirror packages/protocol/schemas/protocol.json.
/// Run packages/flutter/scripts/generate_dart_types.mjs after schema changes.
library;

typedef ProtocolVersion = String;

typedef ErrorCode = String;

typedef CommandAction = String;

class ScreenDestination {
  const ScreenDestination({
    required this.id,
    required this.title,
    required this.description,
    this.params,
    this.reachableFrom,
    this.requiresAuth,
    this.policy,
    this.source,
  });

  final String id;
  final String title;
  final String description;
  final Map<String, dynamic>? params;
  final List<String>? reachableFrom;
  final bool? requiresAuth;
  final String? policy;
  final String? source;

  ScreenDestination copyWith({
    String? id,
    String? title,
    String? description,
    Map<String, dynamic>? params,
    List<String>? reachableFrom,
    bool? requiresAuth,
    String? policy,
    String? source,
  }) {
    return ScreenDestination(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      params: params ?? this.params,
      reachableFrom: reachableFrom ?? this.reachableFrom,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      policy: policy ?? this.policy,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        if (params != null) 'params': params,
        if (reachableFrom != null) 'reachableFrom': reachableFrom,
        if (requiresAuth != null) 'requiresAuth': requiresAuth,
        if (policy != null) 'policy': policy,
        if (source != null) 'source': source,
      };

  factory ScreenDestination.fromJson(Map<String, dynamic> json) {
    return ScreenDestination(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      params: (json['params'] as Map?)?.cast<String, dynamic>(),
      reachableFrom: (json['reachableFrom'] as List?)?.cast<String>(),
      requiresAuth: json['requiresAuth'] as bool?,
      policy: json['policy'] as String?,
      source: json['source'] as String?,
    );
  }
}

class AppInfo {
  const AppInfo({required this.name, required this.description});

  final String name;
  final String description;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
      };

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      name: json['name'] as String,
      description: json['description'] as String,
    );
  }
}

class AppCurrent {
  const AppCurrent({
    required this.screenId,
    required this.stack,
    this.params,
    this.tabs,
  });

  final String screenId;
  final Map<String, dynamic>? params;
  final List<String> stack;
  final List<String>? tabs;

  Map<String, dynamic> toJson() => {
        'screenId': screenId,
        if (params != null) 'params': params,
        'stack': stack,
        if (tabs != null) 'tabs': tabs,
      };

  factory AppCurrent.fromJson(Map<String, dynamic> json) {
    return AppCurrent(
      screenId: json['screenId'] as String,
      params: (json['params'] as Map?)?.cast<String, dynamic>(),
      stack: (json['stack'] as List).cast<String>(),
      tabs: (json['tabs'] as List?)?.cast<String>(),
    );
  }
}

class AppContext {
  const AppContext({
    required this.app,
    required this.current,
    required this.destinations,
  });

  final AppInfo app;
  final AppCurrent current;
  final List<ScreenDestination> destinations;

  AppContext copyWith({
    AppInfo? app,
    AppCurrent? current,
    List<ScreenDestination>? destinations,
  }) {
    return AppContext(
      app: app ?? this.app,
      current: current ?? this.current,
      destinations: destinations ?? this.destinations,
    );
  }

  Map<String, dynamic> toJson() => {
        'app': app.toJson(),
        'current': current.toJson(),
        'destinations': destinations.map((d) => d.toJson()).toList(),
      };

  factory AppContext.fromJson(Map<String, dynamic> json) {
    return AppContext(
      app: AppInfo.fromJson(json['app'] as Map<String, dynamic>),
      current: AppCurrent.fromJson(json['current'] as Map<String, dynamic>),
      destinations: (json['destinations'] as List)
          .map((e) => ScreenDestination.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ElementState {
  const ElementState({
    this.enabled,
    this.focused,
    this.checked,
    this.visible,
  });

  final bool? enabled;
  final bool? focused;
  final bool? checked;
  final bool? visible;

  Map<String, dynamic> toJson() => {
        if (enabled != null) 'enabled': enabled,
        if (focused != null) 'focused': focused,
        if (checked != null) 'checked': checked,
        if (visible != null) 'visible': visible,
      };

  factory ElementState.fromJson(Map<String, dynamic> json) {
    return ElementState(
      enabled: json['enabled'] as bool?,
      focused: json['focused'] as bool?,
      checked: json['checked'] as bool?,
      visible: json['visible'] as bool?,
    );
  }
}

class Bounds {
  const Bounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final num x;
  final num y;
  final num width;
  final num height;

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory Bounds.fromJson(Map<String, dynamic> json) {
    return Bounds(
      x: json['x'] as num,
      y: json['y'] as num,
      width: json['width'] as num,
      height: json['height'] as num,
    );
  }
}

class UiElement {
  const UiElement({
    required this.id,
    required this.role,
    this.label,
    this.value,
    this.state,
    this.bounds,
    this.actions,
    this.children,
    this.redacted,
  });

  final String id;
  final String role;
  final String? label;
  final String? value;
  final ElementState? state;
  final Bounds? bounds;
  final List<String>? actions;
  final List<UiElement>? children;
  final bool? redacted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        if (label != null) 'label': label,
        if (value != null) 'value': value,
        if (state != null) 'state': state!.toJson(),
        if (bounds != null) 'bounds': bounds!.toJson(),
        if (actions != null) 'actions': actions,
        if (children != null) 'children': children!.map((c) => c.toJson()).toList(),
        if (redacted != null) 'redacted': redacted,
      };

  factory UiElement.fromJson(Map<String, dynamic> json) {
    return UiElement(
      id: json['id'] as String,
      role: json['role'] as String,
      label: json['label'] as String?,
      value: json['value'] as String?,
      state: json['state'] != null
          ? ElementState.fromJson(json['state'] as Map<String, dynamic>)
          : null,
      bounds: json['bounds'] != null
          ? Bounds.fromJson(json['bounds'] as Map<String, dynamic>)
          : null,
      actions: (json['actions'] as List?)?.cast<String>(),
      children: (json['children'] as List?)
          ?.map((e) => UiElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      redacted: json['redacted'] as bool?,
    );
  }
}

class Snapshot {
  const Snapshot({
    required this.snapshotId,
    required this.elements,
    required this.capturedAt,
    this.screen,
    this.route,
    this.tokenEstimate,
  });

  final String snapshotId;
  final String? screen;
  final String? route;
  final List<UiElement> elements;
  final num capturedAt;
  final num? tokenEstimate;

  Snapshot copyWith({
    String? snapshotId,
    String? screen,
    String? route,
    List<UiElement>? elements,
    num? capturedAt,
    num? tokenEstimate,
  }) {
    return Snapshot(
      snapshotId: snapshotId ?? this.snapshotId,
      screen: screen ?? this.screen,
      route: route ?? this.route,
      elements: elements ?? this.elements,
      capturedAt: capturedAt ?? this.capturedAt,
      tokenEstimate: tokenEstimate ?? this.tokenEstimate,
    );
  }

  Map<String, dynamic> toJson() => {
        'snapshotId': snapshotId,
        if (screen != null) 'screen': screen,
        if (route != null) 'route': route,
        'elements': elements.map((e) => e.toJson()).toList(),
        'capturedAt': capturedAt,
        if (tokenEstimate != null) 'tokenEstimate': tokenEstimate,
      };

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    return Snapshot(
      snapshotId: json['snapshotId'] as String,
      screen: json['screen'] as String?,
      route: json['route'] as String?,
      elements: (json['elements'] as List)
          .map((e) => UiElement.fromJson(e as Map<String, dynamic>))
          .toList(),
      capturedAt: json['capturedAt'] as num,
      tokenEstimate: json['tokenEstimate'] as num?,
    );
  }
}

class WaitCondition {
  const WaitCondition({
    this.elementId,
    this.labelContains,
    this.timeoutMs,
  });

  final String? elementId;
  final String? labelContains;
  final num? timeoutMs;

  Map<String, dynamic> toJson() => {
        if (elementId != null) 'elementId': elementId,
        if (labelContains != null) 'labelContains': labelContains,
        if (timeoutMs != null) 'timeoutMs': timeoutMs,
      };

  factory WaitCondition.fromJson(Map<String, dynamic> json) {
    return WaitCondition(
      elementId: json['elementId'] as String?,
      labelContains: json['labelContains'] as String?,
      timeoutMs: json['timeoutMs'] as num?,
    );
  }
}

class Command {
  const Command({
    required this.callId,
    required this.action,
    required this.idempotencyKey,
    required this.deadline,
    this.snapshotId,
    this.elementId,
    this.text,
    this.direction,
    this.amount,
    this.screenId,
    this.params,
    this.maxDestinations,
    this.waitCondition,
  });

  final String callId;
  final CommandAction action;
  final String? snapshotId;
  final String idempotencyKey;
  final num deadline;
  final String? elementId;
  final String? text;
  final String? direction;
  final num? amount;
  final String? screenId;
  final Map<String, dynamic>? params;
  final num? maxDestinations;
  final WaitCondition? waitCondition;

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'action': action,
        if (snapshotId != null) 'snapshotId': snapshotId,
        'idempotencyKey': idempotencyKey,
        'deadline': deadline,
        if (elementId != null) 'elementId': elementId,
        if (text != null) 'text': text,
        if (direction != null) 'direction': direction,
        if (amount != null) 'amount': amount,
        if (screenId != null) 'screenId': screenId,
        if (params != null) 'params': params,
        if (maxDestinations != null) 'maxDestinations': maxDestinations,
        if (waitCondition != null) 'waitCondition': waitCondition!.toJson(),
      };

  factory Command.fromJson(Map<String, dynamic> json) {
    return Command(
      callId: json['callId'] as String,
      action: json['action'] as String,
      snapshotId: json['snapshotId'] as String?,
      idempotencyKey: json['idempotencyKey'] as String,
      deadline: json['deadline'] as num,
      elementId: json['elementId'] as String?,
      text: json['text'] as String?,
      direction: json['direction'] as String?,
      amount: json['amount'] as num?,
      screenId: json['screenId'] as String?,
      params: (json['params'] as Map?)?.cast<String, dynamic>(),
      maxDestinations: json['maxDestinations'] as num?,
      waitCondition: json['waitCondition'] != null
          ? WaitCondition.fromJson(json['waitCondition'] as Map<String, dynamic>)
          : null,
    );
  }
}

class CommandResult {
  const CommandResult({
    required this.callId,
    required this.ok,
    this.errorCode,
    this.errorMessage,
    this.snapshot,
    this.appContext,
  });

  final String callId;
  final bool ok;
  final ErrorCode? errorCode;
  final String? errorMessage;
  final Snapshot? snapshot;
  final AppContext? appContext;

  Map<String, dynamic> toJson() => {
        'callId': callId,
        'ok': ok,
        if (errorCode != null) 'errorCode': errorCode,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (snapshot != null) 'snapshot': snapshot!.toJson(),
        if (appContext != null) 'appContext': appContext!.toJson(),
      };

  factory CommandResult.fromJson(Map<String, dynamic> json) {
    return CommandResult(
      callId: json['callId'] as String,
      ok: json['ok'] as bool,
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      snapshot: json['snapshot'] != null
          ? Snapshot.fromJson(json['snapshot'] as Map<String, dynamic>)
          : null,
      appContext: json['appContext'] != null
          ? AppContext.fromJson(json['appContext'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Handshake {
  const Handshake({
    required this.protocolVersion,
    required this.sessionId,
    required this.capabilities,
    this.clientInfo,
  });

  final String type = 'handshake';
  final ProtocolVersion protocolVersion;
  final String sessionId;
  final List<String> capabilities;
  final Map<String, String>? clientInfo;

  Map<String, dynamic> toJson() => {
        'type': type,
        'protocolVersion': protocolVersion,
        'sessionId': sessionId,
        'capabilities': capabilities,
        if (clientInfo != null) 'clientInfo': clientInfo,
      };

  factory Handshake.fromJson(Map<String, dynamic> json) {
    return Handshake(
      protocolVersion: json['protocolVersion'] as String,
      sessionId: json['sessionId'] as String,
      capabilities: (json['capabilities'] as List).cast<String>(),
      clientInfo: (json['clientInfo'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
    );
  }
}

/// Discriminated wire envelope (JSON map with `type`).
typedef WireMessage = Map<String, dynamic>;
