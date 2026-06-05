import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';

import '../utils/logger.dart';

typedef AudioInputStatus = String;

class AudioInputConfig {
  final int sampleRate;
  final int numChannels;
  final void Function(String base64Audio) onAudioChunk;
  final void Function(String error)? onError;
  final void Function()? onPermissionDenied;

  const AudioInputConfig({
    this.sampleRate = 16000,
    this.numChannels = 1,
    required this.onAudioChunk,
    this.onError,
    this.onPermissionDenied,
  });
}

class AudioInputService {
  final AudioInputConfig config;
  final AudioRecorder _permissionRecorder = AudioRecorder();
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();

  StreamController<List<Int16List>>? _recordingDataController;
  StreamSubscription<List<Int16List>>? _streamSubscription;
  bool _initialized = false;
  bool _isRecording = false;
  bool _isMuted = false;
  int _chunkCount = 0;
  int _recordingGeneration = 0;
  Future<void> _operation = Future<void>.value();

  AudioInputService(this.config);

  bool get isRecording => _isRecording;
  bool get isMuted => _isMuted;

  Future<bool> hasPermission({bool request = false}) {
    return _permissionRecorder.hasPermission(request: request);
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final previous = _operation;
    final result = previous.catchError((_) {}).then((_) => action());
    _operation = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  Future<bool> start() {
    return _runExclusive(_start);
  }

  Future<bool> _start() async {
    if (_isRecording) {
      Logger.info('AudioInputService.start() ignored — already recording.');
      return true;
    }

    final generation = ++_recordingGeneration;

    try {
      final hasPermission = await _permissionRecorder.hasPermission();
      if (generation != _recordingGeneration) return false;
      if (!hasPermission) {
        Logger.warn('AudioInputService.start() permission denied.');
        config.onPermissionDenied?.call();
        return false;
      }

      if (!_initialized) {
        await _recorder.openRecorder();
        if (generation != _recordingGeneration) {
          await _recorder.closeRecorder();
          _initialized = false;
          return false;
        }
        _initialized = true;
      }

      _recordingDataController = StreamController<List<Int16List>>();

      _streamSubscription = _recordingDataController!.stream.listen(
        (channels) {
          if (_isMuted || channels.isEmpty || channels.first.isEmpty) return;
          final chunk = _encodePcm16(channels);
          if (chunk.isEmpty) return;
          _chunkCount++;
          if (_chunkCount <= 5 || _chunkCount % 25 == 0) {
            Logger.info(
              'AudioInputService chunk #$_chunkCount (${chunk.length} bytes).',
            );
          }
          config.onAudioChunk(base64Encode(chunk));
        },
        onError: (Object error, StackTrace stackTrace) {
          Logger.error('AudioInputService stream error: $error');
          config.onError?.call(error.toString());
        },
      );

      await _recorder.startRecorder(
        codec: Codec.pcm16,
        toStreamInt16: _recordingDataController!.sink,
        sampleRate: config.sampleRate,
        numChannels: config.numChannels,
        bufferSize: 4096,
        audioSource: AudioSource.microphone,
        enableVoiceProcessing: true,
        enableEchoCancellation: true,
        enableNoiseSuppression: true,
      );

      if (generation != _recordingGeneration) {
        try {
          await _recorder.stopRecorder();
        } catch (error) {
          Logger.warn(
            'AudioInputService.start() stop after cancel failed: $error',
          );
        }
        _isRecording = false;
        return false;
      }

      _isRecording = true;
      Logger.info(
        'AudioInputService started (${config.sampleRate}Hz, ${config.numChannels}ch).',
      );
      return true;
    } catch (error) {
      Logger.error('AudioInputService failed to start: $error');
      config.onError?.call(error.toString());
      return false;
    }
  }

  Future<void> stop() {
    return _runExclusive(_stop);
  }

  Future<void> _stop() async {
    _recordingGeneration++;

    try {
      await _recorder.stopRecorder();
    } catch (error) {
      Logger.warn('AudioInputService.stop() ignored error: $error');
    }

    await _streamSubscription?.cancel();
    _streamSubscription = null;
    await _recordingDataController?.close();
    _recordingDataController = null;

    _isRecording = false;
    _chunkCount = 0;
    Logger.info('AudioInputService stopped.');
  }

  Future<void> mute() async {
    _isMuted = true;
    Logger.info('AudioInputService muted.');
  }

  Future<void> unmute() async {
    _isMuted = false;
    Logger.info('AudioInputService unmuted.');
  }

  Future<void> dispose() async {
    await stop();
    if (_initialized) {
      await _recorder.closeRecorder();
      _initialized = false;
    }
    await _permissionRecorder.dispose();
  }

  Uint8List _encodePcm16(List<Int16List> channels) {
    final frameCount = channels.first.length;
    final channelCount = channels.length;
    final data = ByteData(frameCount * channelCount * 2);
    var offset = 0;

    for (var frame = 0; frame < frameCount; frame++) {
      for (var channel = 0; channel < channelCount; channel++) {
        final samples = channels[channel];
        final sample = frame < samples.length ? samples[frame] : 0;
        data.setInt16(offset, sample, Endian.little);
        offset += 2;
      }
    }

    return data.buffer.asUint8List();
  }
}
