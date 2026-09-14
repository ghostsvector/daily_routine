import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// False when [MurthyAssistantConfig] hasn't been configured (not Linux
/// desktop, or `MURTHY_PYTHON_EXECUTABLE`/`MURTHY_VOICE_REPO_PATH` aren't
/// set in `.env`/`.env.local` — see `main.dart`) — the "Ask Murthy" UI
/// hides itself in that case rather than erroring when tapped.
final murthyAssistantAvailableProvider = Provider<bool>(
  (ref) => MurthyAssistantConfig.isConfigured,
);

/// Each provider owns one long-lived subprocess (see
/// LinuxProcessAssistantService/LinuxProcessVoiceService) — `ref.onDispose`
/// tears it down if the provider itself is ever disposed (it isn't
/// `autoDispose`, so in practice that's only on app shutdown).
final assistantServiceProvider = Provider<AssistantService>((ref) {
  final service = LinuxProcessAssistantService();
  ref.onDispose(service.dispose);
  return service;
});

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = LinuxProcessVoiceService();
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
