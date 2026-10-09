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
    this.toward = 'toward',
    this.findingRoutes = 'Finding routes…',
    this.noRoute = 'No route found',
    this.overview = 'Overview',
    this.exitNavigation = 'Exit navigation',
    this.fastest = 'Fastest',
    this.speedLimit = 'SPEED LIMIT',
    this.mute = 'Mute',
    this.unmute = 'Unmute',
    this.report = 'Report',
    this.compass = 'Compass',
    this.northUp = 'North up',
    this.headingUp = 'Heading up',
    this.addReport = 'Add a report',
    this.reportSent = 'Report sent',
    this.crash = 'Crash',
    this.slowdown = 'Slowdown',
    this.police = 'Police',
    this.construction = 'Construction',
    this.laneClosure = 'Lane closure',
    this.stalledVehicle = 'Stalled vehicle',
    this.objectOnRoad = 'Object on road',
    this.roadClosure = 'Road closure',
    this.sound = 'Sound',
    this.alertsOnly = 'Alerts only',
    this.muted = 'Muted',
    this.searchAlongRoute = 'Search along route',
    this.searchHint = 'Search along the route',
    this.gasStations = 'Gas stations',
    this.restaurants = 'Restaurants',
    this.coffee = 'Coffee',
    this.groceries = 'Groceries',
    this.noResults = 'No results along the route',
    this.searchFailed = 'Search failed',
    this.addStop = 'Add stop',
    this.directions = 'Directions',
    this.shareTrip = 'Share trip progress',
    this.showTraffic = 'Show traffic on map',
    this.satellite = 'Show satellite map',
    this.settings = 'Settings',
    this.routeOptions = 'Route options',
    this.similarEta = 'Similar ETA',
    this.nextStep = 'Next step',
    this.previousStep = 'Previous step',
    this.minFaster = _enMinFaster,
    this.minSlower = _enMinSlower,
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
      toward = 'hướng về',
      findingRoutes = 'Đang tìm đường…',
      noRoute = 'Không tìm thấy đường',
      overview = 'Tổng quan',
      exitNavigation = 'Thoát dẫn đường',
      fastest = 'Nhanh nhất',
      speedLimit = 'TỐC ĐỘ TỐI ĐA',
      mute = 'Tắt tiếng',
      unmute = 'Bật tiếng',
      report = 'Báo cáo',
      compass = 'La bàn',
      northUp = 'Hướng bắc',
      headingUp = 'Theo hướng đi',
      addReport = 'Thêm báo cáo',
      reportSent = 'Đã gửi báo cáo',
      crash = 'Va chạm',
      slowdown = 'Xe chạy chậm',
      police = 'Cảnh sát',
      construction = 'Công trình',
      laneClosure = 'Đóng làn đường',
      stalledVehicle = 'Xe chết máy',
      objectOnRoad = 'Vật cản trên đường',
      roadClosure = 'Đóng đường',
      sound = 'Âm thanh',
      alertsOnly = 'Chỉ cảnh báo',
      muted = 'Đã tắt tiếng',
      searchAlongRoute = 'Tìm dọc đường đi',
      searchHint = 'Tìm địa điểm dọc đường',
      gasStations = 'Trạm xăng',
      restaurants = 'Nhà hàng',
      coffee = 'Cà phê',
      groceries = 'Tạp hoá',
      noResults = 'Không có kết quả dọc đường',
      searchFailed = 'Không tìm được',
      addStop = 'Thêm điểm dừng',
      directions = 'Chỉ đường',
      shareTrip = 'Chia sẻ chuyến đi',
      showTraffic = 'Hiện giao thông trên bản đồ',
      satellite = 'Hiện bản đồ vệ tinh',
      settings = 'Cài đặt',
      routeOptions = 'Tuỳ chọn tuyến đường',
      similarEta = 'Thời gian tương tự',
      nextStep = 'Bước tiếp theo',
      previousStep = 'Bước trước',
      minFaster = _viMinFaster,
      minSlower = _viMinSlower,
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

  /// The "toward" word before a road the route heads for, such as
  /// "toward Main Street".
  final String toward;

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

  /// The "Mute" label (an action: silences the voice guidance).
  final String mute;

  /// The "Unmute" label (an action: turns the voice guidance back on).
  final String unmute;

  /// The "Report" label (reports an incident on the road).
  final String report;

  /// The "Compass" label, for an app's own compass. The packages' compass
  /// buttons are labelled by what a tap does ([northUp] / [headingUp]).
  final String compass;

  /// The "North up" label (the map keeps north at the top).
  final String northUp;

  /// The "Heading up" label (the map turns with the vehicle).
  final String headingUp;

  /// The "Add a report" title of the incident report sheet.
  final String addReport;

  /// The "Report sent" confirmation.
  final String reportSent;

  /// The "Crash" incident.
  final String crash;

  /// The "Slowdown" incident.
  final String slowdown;

  /// The "Police" incident.
  final String police;

  /// The "Construction" incident.
  final String construction;

  /// The "Lane closure" incident.
  final String laneClosure;

  /// The "Stalled vehicle" incident.
  final String stalledVehicle;

  /// The "Object on road" incident.
  final String objectOnRoad;

  /// The "Road closure" incident.
  final String roadClosure;

  /// The "Sound" audio state (turn-by-turn directions and alerts).
  final String sound;

  /// The "Alerts only" audio state (no turn-by-turn directions).
  final String alertsOnly;

  /// The "Muted" audio state (no sound at all).
  final String muted;

  /// The "Search along route" label.
  final String searchAlongRoute;

  /// The hint of the search field along the route.
  final String searchHint;

  /// The "Gas stations" search category.
  final String gasStations;

  /// The "Restaurants" search category.
  final String restaurants;

  /// The "Coffee" search category.
  final String coffee;

  /// The "Groceries" search category.
  final String groceries;

  /// The message shown when a search along the route finds nothing.
  final String noResults;

  /// The message shown when a search along the route fails.
  final String searchFailed;

  /// The "Add stop" label.
  final String addStop;

  /// The "Directions" label (the step list).
  final String directions;

  /// The "Share trip progress" label.
  final String shareTrip;

  /// The "Show traffic on map" label (a toggle).
  final String showTraffic;

  /// The "Show satellite map" label (a toggle).
  final String satellite;

  /// The "Settings" label.
  final String settings;

  /// The "Route options" label (the overview with alternate routes).
  final String routeOptions;

  /// The label of an alternate route as fast as the current one.
  final String similarEta;

  /// The "Next step" label (previews the next manoeuvre).
  final String nextStep;

  /// The "Previous step" label (previews the previous manoeuvre).
  final String previousStep;

  /// The label of an alternate route [minutes] faster: "2 min faster".
  final String Function(int minutes) minFaster;

  /// The label of an alternate route [minutes] slower: "+3 min".
  final String Function(int minutes) minSlower;

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
    String? toward,
    String? findingRoutes,
    String? noRoute,
    String? overview,
    String? exitNavigation,
    String? fastest,
    String? speedLimit,
    String? mute,
    String? unmute,
    String? report,
    String? compass,
    String? northUp,
    String? headingUp,
    String? addReport,
    String? reportSent,
    String? crash,
    String? slowdown,
    String? police,
    String? construction,
    String? laneClosure,
    String? stalledVehicle,
    String? objectOnRoad,
    String? roadClosure,
    String? sound,
    String? alertsOnly,
    String? muted,
    String? searchAlongRoute,
    String? searchHint,
    String? gasStations,
    String? restaurants,
    String? coffee,
    String? groceries,
    String? noResults,
    String? searchFailed,
    String? addStop,
    String? directions,
    String? shareTrip,
    String? showTraffic,
    String? satellite,
    String? settings,
    String? routeOptions,
    String? similarEta,
    String? nextStep,
    String? previousStep,
    String Function(int minutes)? minFaster,
    String Function(int minutes)? minSlower,
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
    toward: toward ?? this.toward,
    findingRoutes: findingRoutes ?? this.findingRoutes,
    noRoute: noRoute ?? this.noRoute,
    overview: overview ?? this.overview,
    exitNavigation: exitNavigation ?? this.exitNavigation,
    fastest: fastest ?? this.fastest,
    speedLimit: speedLimit ?? this.speedLimit,
    mute: mute ?? this.mute,
    unmute: unmute ?? this.unmute,
    report: report ?? this.report,
    compass: compass ?? this.compass,
    northUp: northUp ?? this.northUp,
    headingUp: headingUp ?? this.headingUp,
    addReport: addReport ?? this.addReport,
    reportSent: reportSent ?? this.reportSent,
    crash: crash ?? this.crash,
    slowdown: slowdown ?? this.slowdown,
    police: police ?? this.police,
    construction: construction ?? this.construction,
    laneClosure: laneClosure ?? this.laneClosure,
    stalledVehicle: stalledVehicle ?? this.stalledVehicle,
    objectOnRoad: objectOnRoad ?? this.objectOnRoad,
    roadClosure: roadClosure ?? this.roadClosure,
    sound: sound ?? this.sound,
    alertsOnly: alertsOnly ?? this.alertsOnly,
    muted: muted ?? this.muted,
    searchAlongRoute: searchAlongRoute ?? this.searchAlongRoute,
    searchHint: searchHint ?? this.searchHint,
    gasStations: gasStations ?? this.gasStations,
    restaurants: restaurants ?? this.restaurants,
    coffee: coffee ?? this.coffee,
    groceries: groceries ?? this.groceries,
    noResults: noResults ?? this.noResults,
    searchFailed: searchFailed ?? this.searchFailed,
    addStop: addStop ?? this.addStop,
    directions: directions ?? this.directions,
    shareTrip: shareTrip ?? this.shareTrip,
    showTraffic: showTraffic ?? this.showTraffic,
    satellite: satellite ?? this.satellite,
    settings: settings ?? this.settings,
    routeOptions: routeOptions ?? this.routeOptions,
    similarEta: similarEta ?? this.similarEta,
    nextStep: nextStep ?? this.nextStep,
    previousStep: previousStep ?? this.previousStep,
    minFaster: minFaster ?? this.minFaster,
    minSlower: minSlower ?? this.minSlower,
    via: via ?? this.via,
  );
}

/// English format for "via" phrases.
String _enVia(String summary) => 'via $summary';

/// Vietnamese format for "qua" phrases.
String _viVia(String summary) => 'qua $summary';

/// English label of a faster alternate route.
String _enMinFaster(int minutes) => '$minutes min faster';

/// English label of a slower alternate route.
String _enMinSlower(int minutes) => '+$minutes min';

/// Vietnamese label of a faster alternate route.
String _viMinFaster(int minutes) => 'Nhanh hơn $minutes phút';

/// Vietnamese label of a slower alternate route.
String _viMinSlower(int minutes) => '+$minutes phút';
