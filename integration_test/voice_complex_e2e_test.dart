import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shopflow/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobileai_flutter/mobileai_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'voice handles multi-turn taps, approvals, playback, and resume',
    (tester) async {
      final profileDone = Completer<void>();
      final settingsDone = Completer<void>();
      final darkModeDone = Completer<void>();
      final appearanceSheetDone = Completer<void>();
      final softLavenderDone = Completer<void>();
      final finalPlaybackResumed = Completer<void>();

      final server = await _startComplexFakeLiveServer(
        profileDone: profileDone,
        settingsDone: settingsDone,
        darkModeDone: darkModeDone,
        appearanceSheetDone: appearanceSheetDone,
        softLavenderDone: softLavenderDone,
        finalPlaybackResumed: finalPlaybackResumed,
      );
      addTearDown(() async => server.close(force: true));

      await AIConsentController.grant();
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      await tester.tap(find.byKey(const ValueKey('fab')).hitTestable());
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final consentButton = find.text('Allow AI');
      if (consentButton.evaluate().isNotEmpty) {
        await tester.tap(consentButton.hitTestable());
        await tester.pumpAndSettle(const Duration(seconds: 1));
      }

      await _switchToVoice(tester);

      await _approveNextAction(tester);
      await _pumpUntilComplete(
        tester,
        profileDone.future,
        timeout: const Duration(seconds: 10),
      );
      await _pumpUntilFound(tester, find.text('My Profile'));

      await _approveNextAction(tester);
      await _pumpUntilComplete(
        tester,
        settingsDone.future,
        timeout: const Duration(seconds: 10),
      );
      await _pumpUntilFound(tester, find.text('Profile Settings'));

      await _approveNextAction(tester);
      await _pumpUntilComplete(
        tester,
        darkModeDone.future,
        timeout: const Duration(seconds: 10),
      );
      final darkMode = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, 'Dark Mode'),
      );
      expect(darkMode.value, isTrue);

      await _approveNextAction(tester);
      await _pumpUntilComplete(
        tester,
        appearanceSheetDone.future,
        timeout: const Duration(seconds: 10),
      );
      await _pumpUntilComplete(
        tester,
        softLavenderDone.future,
        timeout: const Duration(seconds: 10),
      );
      await _pumpUntilFound(tester, find.text('Appearance Presets'));
      expect(find.text('Soft Lavender'), findsOneWidget);

      await _pumpUntilComplete(
        tester,
        finalPlaybackResumed.future,
        timeout: const Duration(seconds: 15),
      );
    },
  );
}

Future<void> _switchToVoice(WidgetTester tester) async {
  await _pumpUntilFound(tester, find.text('Voice'));
  final panel = tester.getRect(find.byKey(const ValueKey('expanded')));
  await tester.tapAt(Offset(panel.left + panel.width * 0.75, panel.top + 82));
}

Future<void> _approveNextAction(WidgetTester tester) async {
  await _pumpUntilFound(tester, find.text('Allow'));
  await tester.tap(find.text('Allow'));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpUntilComplete(
  WidgetTester tester,
  Future<void> future, {
  required Duration timeout,
}) async {
  var completed = false;
  Object? failure;
  StackTrace? failureStack;
  unawaited(
    future
        .then((_) {
          completed = true;
        })
        .catchError((Object error, StackTrace stackTrace) {
          failure = error;
          failureStack = stackTrace;
          completed = true;
        }),
  );

  final end = DateTime.now().add(timeout);
  while (!completed && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
  }

  if (!completed) {
    throw TimeoutException('Future did not complete', timeout);
  }
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack ?? StackTrace.current);
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

Future<HttpServer> _startComplexFakeLiveServer({
  required Completer<void> profileDone,
  required Completer<void> settingsDone,
  required Completer<void> darkModeDone,
  required Completer<void> appearanceSheetDone,
  required Completer<void> softLavenderDone,
  required Completer<void> finalPlaybackResumed,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3998);

  server.listen((request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'flags': {}, 'conversations': []}));
      await request.response.close();
      return;
    }

    final socket = await WebSocketTransformer.upgrade(request);
    var latestScreenContext = '';
    var sentProfile = false;
    var sentSettings = false;
    var sentDarkMode = false;
    var sentAppearance = false;
    var sentSoftLavender = false;
    var awaitingPlaybackResume = false;
    var commandNumber = 0;

    void sendAudioDone() {
      _sendAudioDone(socket, 'Done.');
      awaitingPlaybackResume = true;
    }

    void sendNextCommandOnAudio() {
      commandNumber += 1;
      switch (commandNumber) {
        case 1:
          sentProfile = true;
          _sendNavigateToolCall(
            socket,
            id: 'call-profile',
            screen: 'profile',
            transcript: 'go to profile',
          );
          break;
        case 2:
          sentSettings = true;
          _sendTapToolCallForLabel(
            socket,
            id: 'call-settings',
            label: 'Personal Information',
            transcript: 'open account settings',
            screenContext: latestScreenContext,
            onMissingLabel: settingsDone.completeError,
          );
          break;
        case 3:
          sentDarkMode = true;
          _sendTapToolCallForLabel(
            socket,
            id: 'call-dark-mode',
            label: 'Dark Mode',
            transcript: 'turn on dark mode',
            screenContext: latestScreenContext,
            onMissingLabel: darkModeDone.completeError,
          );
          break;
        case 4:
          sentAppearance = true;
          _sendTapToolCallForLabel(
            socket,
            id: 'call-appearance',
            label: 'Appearance Preset',
            transcript: 'open appearance presets and choose soft lavender',
            screenContext: latestScreenContext,
            onMissingLabel: appearanceSheetDone.completeError,
          );
          break;
        default:
          if (!finalPlaybackResumed.isCompleted) {
            finalPlaybackResumed.complete();
          }
      }
    }

    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;

      if (message.containsKey('setup')) {
        socket.add(jsonEncode({'setupComplete': {}}));
        return;
      }

      final contextFromMessage = _screenContextFromMessage(message);
      if (contextFromMessage != null) {
        latestScreenContext = contextFromMessage;
      }

      if (_hasRealtimeAudio(message)) {
        if (awaitingPlaybackResume) {
          awaitingPlaybackResume = false;
          sendNextCommandOnAudio();
          return;
        }
        if (!sentProfile) {
          sendNextCommandOnAudio();
          return;
        }
      }

      final responseIds = _functionResponseIds(message);
      if (responseIds.contains('call-profile')) {
        if (!profileDone.isCompleted) profileDone.complete();
        sendAudioDone();
      }

      if (responseIds.contains('call-settings')) {
        if (!settingsDone.isCompleted) settingsDone.complete();
        sendAudioDone();
      }

      if (responseIds.contains('call-dark-mode')) {
        if (!darkModeDone.isCompleted) darkModeDone.complete();
        sendAudioDone();
      }

      if (responseIds.contains('call-appearance')) {
        if (!appearanceSheetDone.isCompleted) appearanceSheetDone.complete();
        if (!sentSoftLavender) {
          sentSoftLavender = true;
          Future<void>.delayed(const Duration(milliseconds: 300), () {
            _sendTapToolCallForLabel(
              socket,
              id: 'call-soft-lavender',
              label: 'Soft Lavender',
              screenContext: latestScreenContext,
              onMissingLabel: softLavenderDone.completeError,
            );
          });
        }
      }

      if (responseIds.contains('call-soft-lavender')) {
        if (!softLavenderDone.isCompleted) softLavenderDone.complete();
        sendAudioDone();
      }

      if (sentSettings && sentDarkMode && sentAppearance) {
        // Keep analyzer from considering these command-state fields unused in
        // future edits while preserving their log-friendly names.
      }
    });
  });

  return server;
}

void _sendNavigateToolCall(
  WebSocket socket, {
  required String id,
  required String screen,
  required String transcript,
}) {
  _sendTranscript(socket, transcript);
  socket.add(
    jsonEncode({
      'toolCall': {
        'functionCalls': [
          {
            'id': id,
            'name': 'navigate',
            'args': {'screen': screen},
          },
        ],
      },
    }),
  );
}

void _sendTapToolCallForLabel(
  WebSocket socket, {
  required String id,
  required String label,
  required String screenContext,
  String? transcript,
  required void Function(Object error, [StackTrace? stackTrace]) onMissingLabel,
}) {
  final index = _findIndexByLabel(screenContext, label);
  if (index == null) {
    onMissingLabel(
      StateError('Could not find "$label" in context:\n$screenContext'),
    );
    return;
  }
  if (transcript != null) {
    _sendTranscript(socket, transcript);
  }
  socket.add(
    jsonEncode({
      'toolCall': {
        'functionCalls': [
          {
            'id': id,
            'name': 'tap',
            'args': {'index': index},
          },
        ],
      },
    }),
  );
}

void _sendTranscript(WebSocket socket, String text) {
  socket.add(
    jsonEncode({
      'serverContent': {
        'inputTranscription': {'text': text, 'finished': true},
      },
    }),
  );
}

void _sendAudioDone(WebSocket socket, String text) {
  socket.add(
    jsonEncode({
      'serverContent': {
        'modelTurn': {
          'parts': [
            {
              'inlineData': {
                'mimeType': 'audio/pcm;rate=24000',
                'data': 'AAAA',
              },
            },
          ],
        },
        'outputTranscription': {'text': text, 'finished': true},
        'turnComplete': true,
      },
    }),
  );
}

String? _screenContextFromMessage(Map<String, dynamic> message) {
  final clientContent = message['clientContent'];
  if (clientContent is Map<String, dynamic>) {
    final turns = clientContent['turns'];
    if (turns is List) {
      for (final turn in turns) {
        if (turn is! Map<String, dynamic>) continue;
        final parts = turn['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text']?.toString();
          if (text != null && text.contains('Current Screen:')) {
            return text;
          }
        }
      }
    }
  }

  for (final response in _functionResponses(message)) {
    final result = _functionResponseResult(response);
    if (result == null) continue;
    final match = RegExp(
      r'<updated_screen>\s*([\s\S]*?)\s*</updated_screen>',
    ).firstMatch(result);
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

String? _functionResponseResult(Map<String, dynamic> response) {
  final direct = response['result']?.toString();
  if (direct != null) return direct;
  final nested = response['response'];
  if (nested is Map<String, dynamic>) {
    return nested['result']?.toString();
  }
  return null;
}

int? _findIndexByLabel(String context, String label) {
  final pattern = RegExp(r'^\[(\d+)\]<[^>]+>(.*?) />$', multiLine: true);
  for (final match in pattern.allMatches(context)) {
    final candidate = match.group(2)?.trim();
    if (candidate == label || candidate?.contains(label) == true) {
      return int.parse(match.group(1)!);
    }
  }
  return null;
}

bool _hasRealtimeAudio(Map<String, dynamic> message) {
  final realtimeInput = message['realtimeInput'];
  if (realtimeInput is! Map<String, dynamic>) return false;
  return realtimeInput['audio'] != null;
}

List<String> _functionResponseIds(Map<String, dynamic> message) {
  return _functionResponses(message)
      .map((response) => response['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
}

List<Map<String, dynamic>> _functionResponses(Map<String, dynamic> message) {
  final found = <Map<String, dynamic>>[];
  final toolResponse = message['toolResponse'];
  if (toolResponse is Map<String, dynamic>) {
    final responses = toolResponse['functionResponses'];
    if (responses is List) {
      found.addAll(responses.whereType<Map>().map(Map<String, dynamic>.from));
    }
  }

  final clientContent = message['clientContent'];
  if (clientContent is! Map<String, dynamic>) return found;
  final turns = clientContent['turns'];
  if (turns is! List) return found;
  for (final turn in turns) {
    if (turn is! Map<String, dynamic>) continue;
    final parts = turn['parts'];
    if (parts is! List) continue;
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final response = part['functionResponse'];
      if (response is Map<String, dynamic>) {
        found.add(Map<String, dynamic>.from(response));
      }
    }
  }
  return found;
}
