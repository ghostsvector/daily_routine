import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'murthy_background_runner.dart';

enum MurthyVoiceUiState { off, starting, on, unavailable }

/// Drives the settings toggle: starts/stops [MurthyBackgroundRunner] and
/// tracks whether it actually came up (it won't if the wake-word model or
/// access key aren't configured — see `assets/murthy/keywords/README.md`).
class MurthyVoiceController extends StateNotifier<MurthyVoiceUiState> {
  MurthyVoiceController() : super(MurthyVoiceUiState.off) {
    _syncInitialState();
  }

  Future<void> _syncInitialState() async {
    final running = await MurthyBackgroundRunner.isRunning();
    state = running ? MurthyVoiceUiState.on : MurthyVoiceUiState.off;
  }

  Future<void> enable() async {
    state = MurthyVoiceUiState.starting;
    final started = await MurthyBackgroundRunner.start();
    state = started ? MurthyVoiceUiState.on : MurthyVoiceUiState.unavailable;
  }

  Future<void> disable() async {
    await MurthyBackgroundRunner.stop();
    state = MurthyVoiceUiState.off;
  }
}

final murthyVoiceControllerProvider =
    StateNotifierProvider<MurthyVoiceController, MurthyVoiceUiState>(
      (ref) => MurthyVoiceController(),
    );
