/// Words of the Google-style navigation UI (distances, durations and
/// times come from the GuidanceFormatter).
final class GoogleStyleStrings {
  /// Creates the English strings for the Google-style navigation UI.
  const GoogleStyleStrings({
    this.start = 'Start',
    this.resume = 'Resume',
    this.steps = 'Steps',
    this.recenter = 'Re-center',
    this.rerouting = 'Rerouting…',
    this.arrived = 'You have arrived',
    this.done = 'Done',
    this.retry = 'Retry',
    this.cancel = 'Cancel',
    this.then = 'Then',
    this.findingRoutes = 'Finding routes…',
    this.noRoute = 'No route found',
    this.overview = 'Overview',
    this.exitNavigation = 'Exit navigation',
    this.fastest = 'Fastest',
    this.speedLimit = 'SPEED LIMIT',
    this.via = _enVia,
  });

  /// Creates the Vietnamese strings for the Google-style navigation UI.
  const GoogleStyleStrings.vietnamese()
    : start = 'Bắt đầu',
      resume = 'Tiếp tục',
      steps = 'Các bước',
      recenter = 'Căn giữa',
      rerouting = 'Đang tìm đường mới…',
      arrived = 'Bạn đã đến nơi',
      done = 'Xong',
      retry = 'Thử lại',
      cancel = 'Huỷ',
      then = 'Sau đó',
      findingRoutes = 'Đang tìm đường…',
      noRoute = 'Không tìm thấy đường',
      overview = 'Tổng quan',
      exitNavigation = 'Thoát dẫn đường',
      fastest = 'Nhanh nhất',
      speedLimit = 'TỐC ĐỘ TỐI ĐA',
      via = _viVia;

  /// The "Start" label (or equivalent in the chosen language).
  final String start;

  /// The "Resume" label.
  final String resume;

  /// The "Steps" label.
  final String steps;

  /// The "Re-center" label.
  final String recenter;

  /// The "Rerouting…" label.
  final String rerouting;

  /// The "You have arrived" message.
  final String arrived;

  /// The "Done" label.
  final String done;

  /// The "Retry" label.
  final String retry;

  /// The "Cancel" label.
  final String cancel;

  /// The "Then" label.
  final String then;

  /// The "Finding routes…" message.
  final String findingRoutes;

  /// The "No route found" message.
  final String noRoute;

  /// The "Overview" label.
  final String overview;

  /// The "Exit navigation" label.
  final String exitNavigation;

  /// The "Fastest" label.
  final String fastest;

  /// The "SPEED LIMIT" label.
  final String speedLimit;

  /// A function that formats a route summary (e.g., "via A, B").
  final String Function(String summary) via;
}

/// English format for "via" phrases.
String _enVia(String summary) => 'via $summary';

/// Vietnamese format for "qua" phrases.
String _viVia(String summary) => 'qua $summary';
