import 'package:flutter/foundation.dart';

/// OS-level Live Activities / Dynamic Island — placeholders only; failures must
/// never surface to the app (all calls are fully swallowed).
class LiveActivityService {
  LiveActivityService._();

  /// [startTijd] is wall-clock epoch ms (reserved for future native bridges).
  static void startLiveTimer(String taakNaam, int startTijd) {
    try {
      if (kDebugMode) {
        debugPrint('LiveActivityService.start (stub): "$taakNaam" @ $startTijd');
      }
      // Future: e.g. live_activities package — keep strictly inside this try.
    } catch (_) {
      // Intentionally empty: timer UX must never depend on this.
    }
  }

  static void stopLiveTimer() {
    try {
      // Future: end Live Activity session.
    } catch (_) {}
  }
}
