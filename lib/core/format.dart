/// Formats a running call timer as `M:SS` (and `H:MM:SS` once past an hour).
String formatCallClock(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

/// Formats a call duration: `Ns` under a minute, `m:ss` above.
String formatCallDuration(Duration d) {
  final secs = d.inSeconds;
  if (secs < 60) return '${secs}s';
  final m = secs ~/ 60;
  final s = (secs % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Human timing for a call, keeping **ring** and **talk** clearly separate, e.g.
/// "rang 6s · talk 2:15" (answered) or "rang 9s" (not answered). Empty if nothing useful.
String callTimingText({
  required DateTime start,
  DateTime? connected,
  DateTime? end,
}) {
  final parts = <String>[];
  if (connected != null) {
    final ring = connected.difference(start);
    if (ring.inSeconds > 0) parts.add('rang ${formatCallDuration(ring)}');
    if (end != null) parts.add('talk ${formatCallDuration(end.difference(connected))}');
  } else if (end != null) {
    final ring = end.difference(start);
    if (ring.inSeconds > 0) parts.add('rang ${formatCallDuration(ring)}');
  }
  return parts.join(' · ');
}
