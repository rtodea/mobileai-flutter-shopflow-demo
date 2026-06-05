import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../utils/logger.dart';

const int geminiOutputSampleRate = 24000;

class AudioOutputConfig {
  final int sampleRate;
  final int numChannels;
  final void Function()? onPlaybackStart;
  final void Function()? onPlaybackEnd;
  final void Function(String error)? onError;

  const AudioOutputConfig({
    this.sampleRate = geminiOutputSampleRate,
    this.numChannels = 1,
    this.onPlaybackStart,
    this.onPlaybackEnd,
    this.onError,
  });
}

class AudioOutputService {
  final AudioOutputConfig config;
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  AudioSession? _session;
  Future<void> _feedQueue = Future<void>.value();
  bool _initialized = false;
  bool _streamStarted = false;
  bool _muted = false;
  bool _hasStartedPlayback = false;
  int _playbackGeneration = 0;
  Completer<void>? _playbackStopper;

  AudioOutputService({this.config = const AudioOutputConfig()});

  bool get isMuted => _muted;
  bool get isInitialized => _initialized;

  Future<bool> initialize() async {
    if (_initialized) return true;

    try {
      _session = await AudioSession.instance;
      await _session!.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.allowBluetooth |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: false,
        ),
      );

      final activated = await _session!.setActive(true);
      if (!activated) {
        const message = 'Audio session activation was denied by the platform.';
        Logger.warn(message);
        config.onError?.call(message);
        return false;
      }

      await _player.openPlayer();
      await _player.setVolume(1.0);

      _initialized = true;
      Logger.info(
        'AudioOutputService initialized (${config.sampleRate}Hz, ${config.numChannels}ch).',
      );
      return true;
    } catch (error) {
      Logger.error('AudioOutputService failed to initialize: $error');
      config.onError?.call(error.toString());
      return false;
    }
  }

  Future<void> enqueue(String base64Audio) async {
    if (!_initialized) {
      final initialized = await initialize();
      if (!initialized) return;
    }
    if (_muted) return;

    final bytes = base64Decode(base64Audio);
    if (bytes.isEmpty) return;

    final playbackDuration = _estimatePcmDuration(bytes.length);
    _feedQueue = _feedQueue
        .then((_) async {
          if (_muted || !_initialized) return;
          final generation = ++_playbackGeneration;
          await _ensureStreamStarted();
          if (!_hasStartedPlayback) {
            _hasStartedPlayback = true;
            config.onPlaybackStart?.call();
          }
          Logger.info('AudioOutputService enqueue (${bytes.length} bytes).');
          await _player.feedUint8FromStream(Uint8List.fromList(bytes));
          final stopper = Completer<void>();
          _playbackStopper = stopper;
          await Future.any<void>([
            Future<void>.delayed(playbackDuration),
            stopper.future,
          ]);
          if (identical(_playbackStopper, stopper)) {
            _playbackStopper = null;
          }
          if (generation == _playbackGeneration) {
            _hasStartedPlayback = false;
            config.onPlaybackEnd?.call();
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          Logger.error('AudioOutputService feed error: $error');
          config.onError?.call(error.toString());
        });

    await _feedQueue;
  }

  Future<void> stop() async {
    _playbackGeneration++;
    _interruptPlaybackWait();
    await _feedQueue;
    if (_initialized && _streamStarted) {
      try {
        await _player.stopPlayer();
      } catch (error) {
        Logger.warn('AudioOutputService.stop() ignored error: $error');
      }
    }
    _streamStarted = false;
    _hasStartedPlayback = false;
    config.onPlaybackEnd?.call();
  }

  Future<void> mute() async {
    _muted = true;
    if (_initialized) {
      await _player.setVolume(0);
    }
    Logger.info('AudioOutputService muted.');
  }

  Future<void> unmute() async {
    _muted = false;
    if (_initialized) {
      await _player.setVolume(1);
    }
    Logger.info('AudioOutputService unmuted.');
  }

  Future<void> cleanup() async {
    await stop();
    if (_initialized) {
      try {
        await _player.closePlayer();
      } catch (error) {
        Logger.warn('AudioOutputService.cleanup() ignored error: $error');
      }
    }
    _initialized = false;
    _streamStarted = false;
    _session = null;
  }

  void _interruptPlaybackWait() {
    final stopper = _playbackStopper;
    if (stopper != null && !stopper.isCompleted) {
      stopper.complete();
    }
    _playbackStopper = null;
  }

  Future<void> _ensureStreamStarted() async {
    if (_streamStarted) return;
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: config.numChannels,
      sampleRate: config.sampleRate,
      bufferSize: 4096,
    );
    _streamStarted = true;
    Logger.info(
      'AudioOutputService stream started (${config.sampleRate}Hz, ${config.numChannels}ch).',
    );
  }

  Duration _estimatePcmDuration(int byteLength) {
    final bytesPerSample = 2;
    final bytesPerSecond =
        config.sampleRate * config.numChannels * bytesPerSample;
    if (bytesPerSecond <= 0) return const Duration(milliseconds: 200);
    final milliseconds = (byteLength * 1000 / bytesPerSecond).ceil();
    return Duration(milliseconds: milliseconds.clamp(120, 30000).toInt());
  }
}
