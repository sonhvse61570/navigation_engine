import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_engine_flutter/navigation_engine_flutter.dart';

void main() {
  group('NavigationStrings', () {
    test('default constructor creates English strings', () {
      const strings = NavigationStrings();
      expect(strings.start, 'Start');
      expect(strings.resume, 'Resume');
      expect(strings.steps, 'Steps');
    });

    test('via function works in English', () {
      const strings = NavigationStrings();
      expect(strings.via('A, B'), 'via A, B');
    });

    test('vietnamese constructor creates Vietnamese strings', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.start, 'Bắt đầu');
      expect(strings.resume, 'Tiếp tục');
      expect(strings.steps, 'Các bước');
    });

    test('vietnamese via function works', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.via('A'), 'qua A');
    });

    test('custom override works', () {
      const strings = NavigationStrings(start: 'Go');
      expect(strings.start, 'Go');
      expect(strings.resume, 'Resume');
    });

    test('the new English fields', () {
      const strings = NavigationStrings();
      expect(strings.mute, 'Mute');
      expect(strings.unmute, 'Unmute');
      expect(strings.report, 'Report');
      expect(strings.compass, 'Compass');
      expect(strings.northUp, 'North up');
      expect(strings.headingUp, 'Heading up');
    });

    test('the new Vietnamese fields', () {
      const strings = NavigationStrings.vietnamese();
      expect(strings.mute, 'Tắt tiếng');
      expect(strings.unmute, 'Bật tiếng');
      expect(strings.report, 'Báo cáo');
      expect(strings.compass, 'La bàn');
      expect(strings.northUp, 'Hướng bắc');
      expect(strings.headingUp, 'Theo hướng đi');
    });

    test('copyWith changes only the given fields', () {
      const vi = NavigationStrings.vietnamese();
      final copy = vi.copyWith(start: 'Đi', via: (s) => 'ngang $s');
      expect(copy.start, 'Đi');
      expect(copy.via('A'), 'ngang A');
      expect(copy.resume, vi.resume);
      expect(copy.headingUp, vi.headingUp);
      expect(copy.speedLimit, vi.speedLimit);
      final same = vi.copyWith();
      for (final (name, read) in <(String, String Function(NavigationStrings))>[
        ('start', (s) => s.start),
        ('resume', (s) => s.resume),
        ('steps', (s) => s.steps),
        ('recenter', (s) => s.recenter),
        ('rerouting', (s) => s.rerouting),
        ('arrived', (s) => s.arrived),
        ('done', (s) => s.done),
        ('retry', (s) => s.retry),
        ('cancel', (s) => s.cancel),
        ('then', (s) => s.then),
        ('findingRoutes', (s) => s.findingRoutes),
        ('noRoute', (s) => s.noRoute),
        ('overview', (s) => s.overview),
        ('exitNavigation', (s) => s.exitNavigation),
        ('fastest', (s) => s.fastest),
        ('speedLimit', (s) => s.speedLimit),
        ('mute', (s) => s.mute),
        ('unmute', (s) => s.unmute),
        ('report', (s) => s.report),
        ('compass', (s) => s.compass),
        ('northUp', (s) => s.northUp),
        ('headingUp', (s) => s.headingUp),
        ('via', (s) => s.via('A')),
      ]) {
        expect(read(same), read(vi), reason: name);
      }
      // Each field can be set on its own.
      expect(vi.copyWith(compass: 'C').compass, 'C');
      expect(vi.copyWith(compass: 'C').northUp, vi.northUp);
      expect(vi.copyWith(northUp: 'N').northUp, 'N');
      expect(vi.copyWith(mute: 'M').mute, 'M');
      expect(vi.copyWith(exitNavigation: 'X').exitNavigation, 'X');
    });

    test('the SP4 English strings', () {
      const s = NavigationStrings();
      expect(s.addReport, 'Add a report');
      expect(s.reportSent, 'Report sent');
      expect(
        [
          s.crash,
          s.slowdown,
          s.police,
          s.construction,
          s.laneClosure,
          s.stalledVehicle,
          s.objectOnRoad,
          s.roadClosure,
        ],
        [
          'Crash',
          'Slowdown',
          'Police',
          'Construction',
          'Lane closure',
          'Stalled vehicle',
          'Object on road',
          'Road closure',
        ],
      );
      expect(
        [s.sound, s.alertsOnly, s.muted],
        ['Sound', 'Alerts only', 'Muted'],
      );
      expect(s.searchAlongRoute, 'Search along route');
      expect(s.searchHint, 'Search along the route');
      expect(
        [s.gasStations, s.restaurants, s.coffee, s.groceries],
        ['Gas stations', 'Restaurants', 'Coffee', 'Groceries'],
      );
      expect(s.noResults, 'No results along the route');
      expect(s.searchFailed, 'Search failed');
      expect(s.addStop, 'Add stop');
      expect(
        [s.directions, s.shareTrip, s.showTraffic, s.satellite, s.settings],
        [
          'Directions',
          'Share trip progress',
          'Show traffic on map',
          'Show satellite map',
          'Settings',
        ],
      );
      expect(s.routeOptions, 'Route options');
      expect(s.minFaster(2), '2 min faster');
      expect(s.minSlower(3), '+3 min');
      expect(s.similarEta, 'Similar ETA');
      expect(s.nextStep, 'Next step');
      expect(s.previousStep, 'Previous step');
      expect(s.rerouting, 'Rerouting…');
      expect(s.then, 'Then');
      expect(s.arrived, 'You have arrived');
      expect(s.done, 'Done');
    });

    test('the SP4 Vietnamese strings', () {
      const s = NavigationStrings.vietnamese();
      expect(s.report, 'Báo cáo');
      expect(s.addReport, 'Thêm báo cáo');
      expect(s.reportSent, 'Đã gửi báo cáo');
      expect(
        [
          s.crash,
          s.slowdown,
          s.police,
          s.construction,
          s.laneClosure,
          s.stalledVehicle,
          s.objectOnRoad,
          s.roadClosure,
        ],
        [
          'Va chạm',
          'Xe chạy chậm',
          'Cảnh sát',
          'Công trình',
          'Đóng làn đường',
          'Xe chết máy',
          'Vật cản trên đường',
          'Đóng đường',
        ],
      );
      expect(
        [s.sound, s.alertsOnly, s.muted],
        ['Âm thanh', 'Chỉ cảnh báo', 'Đã tắt tiếng'],
      );
      expect(s.searchAlongRoute, 'Tìm dọc đường đi');
      expect(s.searchHint, 'Tìm địa điểm dọc đường');
      expect(
        [s.gasStations, s.restaurants, s.coffee, s.groceries],
        ['Trạm xăng', 'Nhà hàng', 'Cà phê', 'Tạp hoá'],
      );
      expect(s.noResults, 'Không có kết quả dọc đường');
      expect(s.searchFailed, 'Không tìm được');
      expect(s.addStop, 'Thêm điểm dừng');
      expect(
        [s.directions, s.shareTrip, s.showTraffic, s.satellite, s.settings],
        [
          'Chỉ đường',
          'Chia sẻ chuyến đi',
          'Hiện giao thông trên bản đồ',
          'Hiện bản đồ vệ tinh',
          'Cài đặt',
        ],
      );
      expect(s.routeOptions, 'Tuỳ chọn tuyến đường');
      expect(s.minFaster(2), 'Nhanh hơn 2 phút');
      expect(s.minSlower(3), '+3 phút');
      expect(s.similarEta, 'Thời gian tương tự');
      expect(s.nextStep, 'Bước tiếp theo');
      expect(s.previousStep, 'Bước trước');
    });

    test('copyWith keeps and sets the SP4 strings', () {
      const vi = NavigationStrings.vietnamese();
      final same = vi.copyWith();
      for (final (name, read) in <(String, String Function(NavigationStrings))>[
        ('report', (s) => s.report),
        ('addReport', (s) => s.addReport),
        ('reportSent', (s) => s.reportSent),
        ('crash', (s) => s.crash),
        ('slowdown', (s) => s.slowdown),
        ('police', (s) => s.police),
        ('construction', (s) => s.construction),
        ('laneClosure', (s) => s.laneClosure),
        ('stalledVehicle', (s) => s.stalledVehicle),
        ('objectOnRoad', (s) => s.objectOnRoad),
        ('roadClosure', (s) => s.roadClosure),
        ('sound', (s) => s.sound),
        ('alertsOnly', (s) => s.alertsOnly),
        ('muted', (s) => s.muted),
        ('searchAlongRoute', (s) => s.searchAlongRoute),
        ('searchHint', (s) => s.searchHint),
        ('gasStations', (s) => s.gasStations),
        ('restaurants', (s) => s.restaurants),
        ('coffee', (s) => s.coffee),
        ('groceries', (s) => s.groceries),
        ('noResults', (s) => s.noResults),
        ('searchFailed', (s) => s.searchFailed),
        ('addStop', (s) => s.addStop),
        ('directions', (s) => s.directions),
        ('shareTrip', (s) => s.shareTrip),
        ('showTraffic', (s) => s.showTraffic),
        ('satellite', (s) => s.satellite),
        ('settings', (s) => s.settings),
        ('routeOptions', (s) => s.routeOptions),
        ('similarEta', (s) => s.similarEta),
        ('nextStep', (s) => s.nextStep),
        ('previousStep', (s) => s.previousStep),
        ('minFaster', (s) => s.minFaster(4)),
        ('minSlower', (s) => s.minSlower(4)),
      ]) {
        expect(read(same), read(vi), reason: name);
      }
      expect(vi.copyWith(addStop: 'A').addStop, 'A');
      expect(vi.copyWith(addStop: 'A').report, vi.report);
      expect(vi.copyWith(minFaster: (n) => 'F$n').minFaster(2), 'F2');
      expect(vi.copyWith(minSlower: (n) => 'S$n').minSlower(2), 'S2');
    });
  });

  group('Google look wave strings', () {
    test('"toward" in English and Vietnamese', () {
      expect(const NavigationStrings().toward, 'toward');
      expect(const NavigationStrings.vietnamese().toward, 'hướng về');
    });

    test('copyWith keeps and sets toward', () {
      const vi = NavigationStrings.vietnamese();
      expect(vi.copyWith().toward, 'hướng về');
      expect(vi.copyWith(toward: 'T').toward, 'T');
      expect(vi.copyWith(toward: 'T').then, vi.then);
      expect(vi.copyWith(then: 'X').toward, vi.toward);
    });
  });
}
