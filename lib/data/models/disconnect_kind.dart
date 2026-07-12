import 'package:flutter/material.dart';

/// Synthetic disconnect code for a call the OS blocked (CallLog.Calls.BLOCKED_TYPE). Not a real
/// android.telecom.DisconnectCause code — those top out around 11 — so it can't collide.
const int kBlockedDisconnectCode = 9006;

/// A call-log entry's outcome, derived from direction + whether it connected + the raw
/// disconnect code. Using `connected` avoids mislabeling an unanswered incoming call as
/// "Error" — it's a Missed call.
class CallDisposition {
  const CallDisposition(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

CallDisposition dispositionFor({
  required String direction,
  required bool connected,
  required int? disconnectCode,
}) {
  final incoming = direction == 'incoming';
  final kind = DisconnectKind.fromAndroidCode(disconnectCode);
  if (incoming) {
    if (connected) return const CallDisposition('Incoming', Icons.call_received, Colors.green);
    if (kind == DisconnectKind.blocked) {
      return const CallDisposition('Blocked', Icons.block, Colors.red);
    }
    if (kind == DisconnectKind.rejected) {
      return const CallDisposition('Declined', Icons.do_not_disturb_on, Colors.orange);
    }
    return const CallDisposition('Missed', Icons.call_missed, Colors.red);
  }
  if (connected) return const CallDisposition('Outgoing', Icons.call_made, Colors.green);
  if (kind == DisconnectKind.busy) {
    return const CallDisposition('Busy', Icons.phone_disabled, Colors.orange);
  }
  if (kind == DisconnectKind.canceled) {
    return const CallDisposition('Cancelled', Icons.call_missed_outgoing, Colors.orange);
  }
  return const CallDisposition('No answer', Icons.call_missed_outgoing, Colors.orange);
}

/// Feature #1 — who ended the call. Mirrors android.telecom.DisconnectCause codes and
/// maps them to a user-facing disposition with an icon for the call log.
enum DisconnectKind {
  /// We (the local user) hung up.
  local,

  /// The remote party hung up.
  remote,

  /// Outgoing call we canceled before it connected.
  canceled,

  /// Incoming call we never answered.
  missed,

  /// We rejected the incoming call.
  rejected,

  /// The OS blocked the incoming call (blocklist / screening).
  blocked,

  /// Remote line was busy.
  busy,

  /// Answered on another device.
  answeredElsewhere,

  error,
  unknown;

  /// Maps an Android `DisconnectCause.getCode()` value.
  static DisconnectKind fromAndroidCode(int? code) {
    switch (code) {
      case kBlockedDisconnectCode:
        return DisconnectKind.blocked;
      case 2:
        return DisconnectKind.local;
      case 3:
        return DisconnectKind.remote;
      case 4:
        return DisconnectKind.canceled;
      case 5:
        return DisconnectKind.missed;
      case 6:
        return DisconnectKind.rejected;
      case 7:
        return DisconnectKind.busy;
      case 11:
        return DisconnectKind.answeredElsewhere;
      case 1:
        return DisconnectKind.error;
      default:
        return DisconnectKind.unknown;
    }
  }

  String get label => switch (this) {
        DisconnectKind.local => 'You ended',
        DisconnectKind.remote => 'They ended',
        DisconnectKind.canceled => 'Canceled',
        DisconnectKind.missed => 'Missed',
        DisconnectKind.rejected => 'Declined',
        DisconnectKind.blocked => 'Blocked',
        DisconnectKind.busy => 'Busy',
        DisconnectKind.answeredElsewhere => 'Answered elsewhere',
        DisconnectKind.error => 'Error',
        DisconnectKind.unknown => 'Unknown',
      };

  IconData get icon => switch (this) {
        DisconnectKind.local => Icons.call_end,
        DisconnectKind.remote => Icons.call_received,
        DisconnectKind.canceled => Icons.call_missed_outgoing,
        DisconnectKind.missed => Icons.call_missed,
        DisconnectKind.rejected => Icons.do_not_disturb_on,
        DisconnectKind.blocked => Icons.block,
        DisconnectKind.busy => Icons.phone_disabled,
        DisconnectKind.answeredElsewhere => Icons.devices,
        DisconnectKind.error => Icons.error_outline,
        DisconnectKind.unknown => Icons.help_outline,
      };
}
