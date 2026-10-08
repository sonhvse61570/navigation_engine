/// Words of the navigation UIs (all styles). Distances, durations, times and
/// speeds come from the GuidanceFormatter.
final class NavigationStrings {
  /// Creates the English strings for the navigation UIs.
  const NavigationStrings({
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
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.reportIncident = 'Report',
    this.compass = 'Compass',
    this.northUp = 'North up',
    this.headingUp = 'Heading up',
    this.via = _enVia,
  });

  /// Creates the Vietnamese strings for the navigation UIs.
  const NavigationStrings.vietnamese()
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
      mute = 'Tắt tiếng',
      unmute = 'Bật tiếng',
      reportIncident = 'Báo cáo',
      compass = 'La bàn',
      northUp = 'Hướng bắc',
      headingUp = 'Theo hướng đi',
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

  /// The "Mute" label (silences the voice guidance).
  final String mute;

  /// The "Unmute" label (turns the voice guidance back on).
  final String unmute;

  /// The "Report" label (reports an incident on the road).
  final String reportIncident;

  /// The "Compass" label, for an app's own compass. The packages' compass
  /// buttons are labelled by what a tap does ([northUp] / [headingUp]).
  final String compass;

  /// The "North up" label (the map keeps north at the top).
  final String northUp;

  /// The "Heading up" label (the map turns with the vehicle).
  final String headingUp;

  /// A function that formats a route summary (e.g., "via A, B").
  final String Function(String summary) via;

  /// A copy with the given strings replaced, such as one word of
  /// [NavigationStrings.vietnamese]; the others are kept.
  NavigationStrings copyWith({
    String? start,
    String? resume,
    String? steps,
    String? recenter,
    String? rerouting,
    String? arrived,
    String? done,
    String? retry,
    String? cancel,
    String? then,
    String? findingRoutes,
    String? noRoute,
    String? overview,
    String? exitNavigation,
    String? fastest,
    String? speedLimit,
    String? mute,
    String? unmute,
    String? reportIncident,
    String? compass,
    String? northUp,
    String? headingUp,
    String Function(String summary)? via,
  }) => NavigationStrings(
    start: start ?? this.start,
    resume: resume ?? this.resume,
    steps: steps ?? this.steps,
    recenter: recenter ?? this.recenter,
    rerouting: rerouting ?? this.rerouting,
    arrived: arrived ?? this.arrived,
    done: done ?? this.done,
    retry: retry ?? this.retry,
    cancel: cancel ?? this.cancel,
    then: then ?? this.then,
    findingRoutes: findingRoutes ?? this.findingRoutes,
    noRoute: noRoute ?? this.noRoute,
    overview: overview ?? this.overview,
    exitNavigation: exitNavigation ?? this.exitNavigation,
    fastest: fastest ?? this.fastest,
    speedLimit: speedLimit ?? this.speedLimit,
    mute: mute ?? this.mute,
    unmute: unmute ?? this.unmute,
    reportIncident: reportIncident ?? this.reportIncident,
    compass: compass ?? this.compass,
    northUp: northUp ?? this.northUp,
    headingUp: headingUp ?? this.headingUp,
    via: via ?? this.via,
  );
}

/// English format for "via" phrases.
String _enVia(String summary) => 'via $summary';

/// Vietnamese format for "qua" phrases.
String _viVia(String summary) => 'qua $summary';
