/// Cross-platform ping output parser.
///
/// Handles the stdout from Windows `ping -n`, macOS/Linux `ping -c`,
/// and extracts round-trip time statistics.
class PingParser {
  PingParser._();

  /// Parse the raw stdout from a `ping` command and return the average
  /// round-trip time in milliseconds, or `null` if parsing fails or the
  /// host is unreachable.
  ///
  /// [rawOutput] — the complete stdout from the ping command.
  /// [isWindows]  — `true` if the output came from Windows `ping.exe`.
  static int? parseLatency(String rawOutput, {required bool isWindows}) {
    if (rawOutput.isEmpty) return null;

    if (isWindows) {
      return _parseWindows(rawOutput);
    } else {
      return _parseUnix(rawOutput);
    }
  }

  /// Parse ping statistics returned from the platform channel as a map.
  ///
  /// Expects a map with numeric keys `min`, `avg`, `max` (all in ms).
  /// On Windows the map may only contain `avg`.
  static int? parseStatsMap(Map<dynamic, dynamic>? stats) {
    if (stats == null) return null;
    final avg = stats['avg'];
    if (avg is int) return avg;
    if (avg is double) return avg.round();
    if (avg is String) return int.tryParse(avg);
    return null;
  }

  // --- internals -----------------------------------------------------------

  /// Windows: look for "Average = XXms" (English) or "Media = XXms" (Spanish).
  static int? _parseWindows(String raw) {
    // English: "Average = 42ms"
    final eng = RegExp(r'Average\s*=\s*(\d+)\s*ms', caseSensitive: false);
    final engMatch = eng.firstMatch(raw);
    if (engMatch != null) {
      return int.tryParse(engMatch.group(1)!);
    }

    // Spanish: "Media = 42ms"
    final spa = RegExp(r'Media\s*=\s*(\d+)\s*ms', caseSensitive: false);
    final spaMatch = spa.firstMatch(raw);
    if (spaMatch != null) {
      return int.tryParse(spaMatch.group(1)!);
    }

    // Fallback: look for "Minimum = Xms, Maximum = Yms, Average = Zms"
    final fallback = RegExp(r'(\d+)\s*ms', caseSensitive: false);
    final matches = fallback.allMatches(raw).toList();
    if (matches.length >= 3) {
      // The last numeric value before "ms" in the stats line is average
      return int.tryParse(matches.last.group(1)!);
    }

    return null;
  }

  /// macOS / Linux: look for "min/avg/max/mdev" or "min/avg/max/stddev".
  static int? _parseUnix(String raw) {
    // Format: "round-trip min/avg/max/stddev = 10.123/42.456/100.789/20.111 ms"
    // or     "rtt min/avg/max/mdev = 10.123/42.456/100.789/20.111 ms"
    final rtt = RegExp(
      r'(?:round-trip|rtt)\s+min/avg/max/(?:mdev|stddev)\s*=\s*'
      r'([\d.]+)/([\d.]+)/([\d.]+)/([\d.]+)\s*ms',
      caseSensitive: false,
    );
    final match = rtt.firstMatch(raw);
    if (match != null) {
      // match.group(2) is "avg"
      final avg = double.tryParse(match.group(2)!);
      return avg?.round();
    }

    // Fallback: look for "avg" line (e.g., "avg = 42.0ms")
    final avgLine = RegExp(r'avg\s*=\s*([\d.]+)\s*ms', caseSensitive: false);
    final avgMatch = avgLine.firstMatch(raw);
    if (avgMatch != null) {
      final avg = double.tryParse(avgMatch.group(1)!);
      return avg?.round();
    }

    // Second fallback: try to extract any ms values after "packets transmitted"
    // and take an average-like value
    final statsLine = RegExp(
      r'(\d+)\s*packets transmitted.*\n.*',
      caseSensitive: false,
    );
    if (statsLine.hasMatch(raw)) {
      // If we have packet stats but no RTT line, host might be unreachable.
      final lossReg = RegExp(r'(\d+)%\s*packet loss', caseSensitive: false);
      final lossMatch = lossReg.firstMatch(raw);
      if (lossMatch != null) {
        final loss = int.tryParse(lossMatch.group(1)!);
        if (loss == 100) return null; // all packets lost
      }
    }

    return null;
  }
}
