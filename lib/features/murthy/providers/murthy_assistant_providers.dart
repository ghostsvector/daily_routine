import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether "Ask Murthy" should show itself at all: unconditionally true on
/// Android (self-contained — downloads its own model, no setup needed);
/// on Linux desktop, only once [MurthyAssistantConfig] has been configured
/// (`MURTHY_PYTHON_EXECUTABLE`/`MURTHY_VOICE_REPO_PATH` in `.env`/
/// `.env.local` — see `main.dart`); false everywhere else (no
/// implementation yet).
final murthyAssistantAvailableProvider = Provider<bool>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return true;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
    return MurthyAssistantConfig.isConfigured;
  }
  return false;
});

/// Each provider owns one long-lived engine/subprocess — `ref.onDispose`
/// tears it down if the provider itself is ever disposed (it isn't
/// `autoDispose`, so in practice that's only on app shutdown).
final assistantServiceProvider = Provider<AssistantService>((ref) {
  final AssistantService service = defaultTargetPlatform == TargetPlatform.android
      ? AndroidLlamaAssistantService()
      : LinuxProcessAssistantService();
  ref.onDispose(service.dispose);
  return service;
});

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final VoiceService service = defaultTargetPlatform == TargetPlatform.android
      ? FlutterTtsVoiceService()
      : LinuxProcessVoiceService();
  ref.onDispose(service.dispose);
  return service;
});

/// "Hey Murthy": a real wake-word engine on Linux, a continuous-listening
/// approximation on Android (see [AndroidSpeechWakeWordService]'s doc
/// comment for why).
final wakeWordServiceProvider = Provider<WakeWordService>((ref) {
  final WakeWordService service = defaultTargetPlatform == TargetPlatform.android
      ? AndroidSpeechWakeWordService()
      : LinuxProcessWakeWordService();
  ref.onDispose(service.dispose);
  return service;
});

/// Telugu if [text] contains any Telugu-block character, else English —
/// mirrors `murthy-voice`'s `tts.detect_language`, used here to pick which
/// voice speaks Murthy's answer.
String detectSpokenLanguage(String text) {
  final hasTelugu = text.runes.any((r) => r >= 0x0C00 && r <= 0x0C7F);
  return hasTelugu ? 'te' : 'en';
}
