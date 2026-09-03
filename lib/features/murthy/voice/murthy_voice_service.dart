import 'dart:async';
import 'dart:typed_data';

import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/murthy_repository.dart';
import '../providers/murthy_providers.dart' show todayKey;
import 'murthy_wakeword_engine.dart';
import 'murthy_wakeword_models.dart';

enum MurthyVoiceStatus {
  stopped,
  starting,
  listeningForWakeWord,
  respondingToCommand,
  unavailable,
}

/// Core "Hey Murthy" logic: wake-word detection (openWakeWord, run locally
/// via ONNX Runtime — see `murthy_wakeword_engine.dart`) → spoken
/// acknowledgement + a short speech-to-text window for a command
/// (flutter_tts / speech_to_text) → a handful of hardcoded commands read
/// back from the same encrypted Murthy data the app screen shows.
///
/// Platform-agnostic on purpose — see `murthy_background_runner.dart` for
/// how it's kept alive per platform (a background service on
/// Android/iOS, the plain app process on desktop).
class MurthyVoiceService {
  MurthyVoiceService({
    required this.authService,
    required this.routineRepository,
    required this.murthyRepository,
  });

  final AuthService authService;
  final RoutineRepositoryService routineRepository;
  final MurthyRepository murthyRepository;

  final _tts = FlutterTts();
  final _stt = SpeechToText();
  final _recorder = AudioRecorder();

  MurthyWakewordModels? _models;
  MurthyWakewordEngine? _engine;
  StreamSubscription<Uint8List>? _audioSubscription;

  final _statusController = StreamController<MurthyVoiceStatus>.broadcast();
  Stream<MurthyVoiceStatus> get statusStream => _statusController.stream;
  MurthyVoiceStatus _status = MurthyVoiceStatus.stopped;

  void _setStatus(MurthyVoiceStatus status) {
    _status = status;
    _statusController.add(status);
  }

  bool get isRunning =>
      _status != MurthyVoiceStatus.stopped &&
      _status != MurthyVoiceStatus.unavailable;

  /// Starts always-on wake-word listening. Returns `false` (and leaves
  /// status at [MurthyVoiceStatus.unavailable]) if the ONNX models aren't
  /// bundled yet — see `assets/murthy/onnx/README.md` — or the mic
  /// permission was denied.
  Future<bool> start() async {
    if (isRunning) return true;
    _setStatus(MurthyVoiceStatus.starting);

    final models = await MurthyWakewordModels.loadIfAvailable();
    if (models == null) {
      _setStatus(MurthyVoiceStatus.unavailable);
      return false;
    }

    final sttReady = await _stt.initialize();
    final micGranted = await _recorder.hasPermission();
    if (!sttReady || !micGranted) {
      models.release();
      _setStatus(MurthyVoiceStatus.unavailable);
      return false;
    }

    _models = models;
    _engine = MurthyWakewordEngine(models);

    final audioStream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    _audioSubscription = audioStream.listen(_onAudioChunk);

    _setStatus(MurthyVoiceStatus.listeningForWakeWord);
    return true;
  }

  Future<void> stop() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _recorder.stop();
    await _stt.stop();
    await _tts.stop();
    _models?.release();
    _models = null;
    _engine = null;
    _setStatus(MurthyVoiceStatus.stopped);
  }

  Future<void> _onAudioChunk(Uint8List bytes) async {
    if (_status != MurthyVoiceStatus.listeningForWakeWord) return;
    final engine = _engine;
    if (engine == null) return;

    final samples = bytes.buffer.asInt16List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 2,
    );
    final scores = await engine.pushAudio(samples);
    if (scores.any((score) => score >= engine.detectionThreshold)) {
      await _onWakeWordDetected();
    }
  }

  Future<void> _onWakeWordDetected() async {
    if (_status != MurthyVoiceStatus.listeningForWakeWord) return;
    _setStatus(MurthyVoiceStatus.respondingToCommand);

    await _tts.speak('Hi sir');
    final command = await _listenForCommand();
    final reply = await _handleCommand(command);
    await _tts.speak(reply);

    if (_engine != null) {
      _setStatus(MurthyVoiceStatus.listeningForWakeWord);
    }
  }

  Future<String> _listenForCommand() async {
    // The mic is exclusive between the raw PCM stream (for wake-word
    // detection) and the OS speech recognizer — pause the former while
    // capturing a command, then resume once done.
    await _audioSubscription?.cancel();
    await _recorder.stop();

    final completer = Completer<String>();
    var heard = '';
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(seconds: 2),
      ),
      onResult: (SpeechRecognitionResult result) {
        heard = result.recognizedWords;
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(heard);
        }
      },
    );
    final result = await completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => heard,
    );
    await _stt.stop();

    if (isRunning) {
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _audioSubscription = audioStream.listen(_onAudioChunk);
    }
    return result;
  }

  Future<String> _handleCommand(String command) async {
    final normalized = command.toLowerCase();
    final uid = authService.currentUser.uid;
    if (uid.isEmpty) {
      return "I can't reach your account right now — please sign in first.";
    }

    if (normalized.contains('progress')) {
      final tasks = await routineRepository.watchTasks(uid).first;
      final today = DateTime.now().weekday;
      final todays = tasks.where((t) => t.occursOnWeekday(today)).toList();
      final completed = todays.where((t) => t.isCompletedToday).length;
      return 'You have completed $completed of ${todays.length} tasks today.';
    }

    if (normalized.contains('protocol')) {
      final protocols = await murthyRepository.fetchProtocolsOnce(uid);
      final active = protocols.where((p) => p.isActive).length;
      return 'You have ${protocols.length} daily protocols, $active active.';
    }

    if (normalized.contains('summary')) {
      final entry = await murthyRepository.watchProgress(uid, todayKey()).first;
      return entry.summary.isEmpty
          ? "You haven't written today's summary yet."
          : entry.summary;
    }

    return "Hi sir, how can I help? You can ask for your progress, protocols, or today's summary.";
  }
}
