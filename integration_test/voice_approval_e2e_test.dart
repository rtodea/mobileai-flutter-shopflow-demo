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

  testWidgets('voice command requests approval and navigates after Allow', (
    tester,
  ) async {
    final profileFunctionResponseReceived = Completer<void>();
    final postProfileAudioReceived = Completer<void>();
    final homeFunctionResponseReceived = Completer<void>();
    final server = await _startFakeLiveServer(
      profileFunctionResponseReceived,
      postProfileAudioReceived,
      homeFunctionResponseReceived,
    );
    addTearDown(() async => server.close(force: true));

    await AIConsentController.grant();
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    await tester.tap(find.byKey(const ValueKey('fab')).hitTestable());
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('expanded')), findsOneWidget);

    final consentButton = find.text('Allow AI');
    if (consentButton.evaluate().isNotEmpty) {
      await tester.tap(consentButton.hitTestable());
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    await _pumpUntilFound(tester, find.text('Voice'));
    final panel = tester.getRect(find.byKey(const ValueKey('expanded')));
    await tester.tapAt(Offset(panel.left + panel.width * 0.75, panel.top + 82));
    await _pumpUntilFound(tester, find.text('Allow'));

    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('My Profile'), findsNothing);

    await tester.tap(find.text('Allow'));
    await _pumpUntilFound(tester, find.text('My Profile'));
    expect(find.text('John Doe'), findsOneWidget);

    await _pumpUntilComplete(
      tester,
      profileFunctionResponseReceived.future,
      timeout: const Duration(seconds: 5),
    );
    await _pumpUntilComplete(
      tester,
      postProfileAudioReceived.future,
      timeout: const Duration(seconds: 15),
    );
    await _pumpUntilFound(tester, find.text('Allow'));
    await tester.tap(find.text('Allow'));
    await _pumpUntilComplete(
      tester,
      homeFunctionResponseReceived.future,
      timeout: const Duration(seconds: 15),
    );
    await tester.pumpAndSettle(const Duration(seconds: 4));
    expect(find.text('Shop by Category'), findsOneWidget);
  });
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

Future<HttpServer> _startFakeLiveServer(
  Completer<void> profileFunctionResponseReceived,
  Completer<void> postProfileAudioReceived,
  Completer<void> homeFunctionResponseReceived,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 3999);

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
    var receivedScreenContext = false;
    var sentProfileToolCall = false;
    var profileToolCompleted = false;
    var sentHomeToolCall = false;

    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;

      if (message.containsKey('setup')) {
        socket.add(jsonEncode({'setupComplete': {}}));
        return;
      }

      if (message.containsKey('clientContent')) {
        receivedScreenContext = true;
        return;
      }

      if (_hasRealtimeAudio(message) &&
          receivedScreenContext &&
          !sentProfileToolCall) {
        sentProfileToolCall = true;
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _sendNavigateToolCall(
            socket,
            id: 'call-profile-1',
            screen: 'profile',
          );
        });
        return;
      }

      if (_hasRealtimeAudio(message) &&
          profileToolCompleted &&
          !sentHomeToolCall) {
        sentHomeToolCall = true;
        if (!postProfileAudioReceived.isCompleted) {
          postProfileAudioReceived.complete();
        }
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          _sendNavigateToolCall(socket, id: 'call-home-1', screen: 'home');
        });
        return;
      }

      final responseIds = _functionResponseIds(message);
      if (responseIds.contains('call-profile-1')) {
        profileToolCompleted = true;
        if (!profileFunctionResponseReceived.isCompleted) {
          profileFunctionResponseReceived.complete();
        }
        _sendAudioDone(socket);
      }

      if (responseIds.contains('call-home-1')) {
        if (!homeFunctionResponseReceived.isCompleted) {
          homeFunctionResponseReceived.complete();
        }
        _sendAudioDone(socket);
      }
    });
  });

  return server;
}

void _sendNavigateToolCall(
  WebSocket socket, {
  required String id,
  required String screen,
}) {
  socket.add(
    jsonEncode({
      'serverContent': {
        'inputTranscription': {'text': 'go to $screen', 'finished': true},
      },
    }),
  );
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

void _sendAudioDone(WebSocket socket) {
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
        'outputTranscription': {'text': 'Done.', 'finished': true},
        'turnComplete': true,
      },
    }),
  );
}

bool _hasRealtimeAudio(Map<String, dynamic> message) {
  final realtimeInput = message['realtimeInput'];
  if (realtimeInput is! Map<String, dynamic>) return false;
  return realtimeInput['audio'] != null;
}

List<String> _functionResponseIds(Map<String, dynamic> message) {
  final ids = <String>[];
  final toolResponse = message['toolResponse'];
  if (toolResponse is Map<String, dynamic>) {
    final responses = toolResponse['functionResponses'];
    if (responses is List) {
      ids.addAll(
        responses
            .whereType<Map>()
            .map((response) => response['id']?.toString() ?? '')
            .where((id) => id.isNotEmpty),
      );
    }
  }

  final clientContent = message['clientContent'];
  if (clientContent is! Map<String, dynamic>) return ids;
  final turns = clientContent['turns'];
  if (turns is! List) return ids;
  for (final turn in turns) {
    if (turn is! Map<String, dynamic>) continue;
    final parts = turn['parts'];
    if (parts is! List) continue;
    for (final part in parts) {
      if (part is! Map<String, dynamic>) continue;
      final response = part['functionResponse'];
      if (response is Map<String, dynamic>) {
        final id = response['id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
  }
  return ids;
}
