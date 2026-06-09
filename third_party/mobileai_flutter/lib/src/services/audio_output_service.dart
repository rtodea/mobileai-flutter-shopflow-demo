import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_sound/flutter_sound.dart';

import '../utils/logger.dart';

const int geminiOutputSampleRate = 24000;

// Size of the flutter_sound stream player's internal buffer. Gemini Live
// streams ~40ms PCM chunks; a larger buffer gives the native AudioTrack
// headroom to absorb network jitter between chunks so it does not underrun.
const int _streamBufferSize = 16384;

// How long playback must stay quiet (no new audio fed) before we treat the
// utterance as finished. Must comfortably exceed the buffer drain time so
// onPlaybackEnd is not fired while buffered audio is still playing.
const Duration _playbackEndDebounce = Duration(milliseconds: 500);

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
  Timer? _endTimer;
  bool _initialized = false;
  bool _streamStarted = false;
  bool _muted = false;
  bool _hasStartedPlayback = false;

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

    _feedQueue = _feedQueue
        .then((_) async {
          if (_muted || !_initialized) return;
          await _ensureStreamStarted();
          if (!_hasStartedPlayback) {
            _hasStartedPlayback = true;
            config.onPlaybackStart?.call();
          }
          Logger.info('AudioOutputService enqueue (${bytes.length} bytes).');
          // flutter_sound applies its own flow control: this future completes
          // once the player is ready for more data, so feeding chunks
          // back-to-back paces them to real-time playback. The previous
          // version inserted an inflated per-chunk delay here (a 120ms floor
          // against ~40ms chunks), which starved the native AudioTrack and
          // produced the underrun/choppy playback.
          await _player.feedUint8FromStream(Uint8List.fromList(bytes));
          _scheduleEnd();
        })
        .catchError((Object error, StackTrace stackTrace) {
          Logger.error('AudioOutputService feed error: $error');
          config.onError?.call(error.toString());
        });

    await _feedQueue;
  }

  // Fire onPlaybackEnd once no further audio has arrived for long enough that
  // the player buffer has drained. Reset on every chunk, so it only triggers
  // at the true end of an utterance rather than between chunks.
  void _scheduleEnd() {
    _endTimer?.cancel();
    _endTimer = Timer(_playbackEndDebounce, () {
      _endTimer = null;
      if (_hasStartedPlayback) {
        _hasStartedPlayback = false;
        config.onPlaybackEnd?.call();
      }
    });
  }

  Future<void> stop() async {
    _endTimer?.cancel();
    _endTimer = null;
    if (_initialized && _streamStarted) {
      try {
        // Stop first so any feed currently blocked on backpressure unwinds.
        await _player.stopPlayer();
      } catch (error) {
        Logger.warn('AudioOutputService.stop() ignored error: $error');
      }
    }
    try {
      await _feedQueue;
    } catch (_) {}
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

  Future<void> _ensureStreamStarted() async {
    if (_streamStarted) return;
    await _player.startPlayerFromStream(
      codec: Codec.pcm16,
      interleaved: true,
      numChannels: config.numChannels,
      sampleRate: config.sampleRate,
      bufferSize: _streamBufferSize,
    );
    _streamStarted = true;
    Logger.info(
      'AudioOutputService stream started (${config.sampleRate}Hz, ${config.numChannels}ch).',
    );
  }
}
