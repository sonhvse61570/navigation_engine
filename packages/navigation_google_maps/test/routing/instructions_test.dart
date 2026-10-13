import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_google_maps/src/routing/instructions.dart';

void main() {
  test('English: the name after "onto" or "on"', () {
    const cases = {
      'Turn left onto Pasteur': 'Pasteur',
      'Head northeast on Lê Lợi toward Pasteur': 'Lê Lợi',
      'Continue straight to stay on Đồng Khởi': 'Đồng Khởi',
      'At the roundabout, take the 2nd exit onto Đồng Khởi': 'Đồng Khởi',
      'Keep left to continue on QL1A': 'QL1A',
      'Take the exit onto Võ Văn Kiệt, toward Quận 5': 'Võ Văn Kiệt',
      'Merge onto Mai Chí Thọ.': 'Mai Chí Thọ',
      // "onto" wins over an earlier or later "on".
      'Turn right on the ramp onto Xa lộ Hà Nội': 'Xa lộ Hà Nội',
      'TURN LEFT ONTO Hai Bà Trưng': 'Hai Bà Trưng',
    };
    for (final MapEntry(key: text, value: name) in cases.entries) {
      expect(roadNameOf(text), name, reason: text);
    }
  });

  test('Vietnamese: the name after "vào", "sang", "đi tiếp" or "trên"', () {
    const cases = {
      'Rẽ trái vào Pasteur': 'Pasteur',
      'Chếch sang phải vào Lê Duẩn': 'Lê Duẩn',
      'Rẽ phải sang Hai Bà Trưng': 'Hai Bà Trưng',
      'Đi tiếp Nguyễn Huệ': 'Nguyễn Huệ',
      'Tiếp tục đi thẳng để đi tiếp trên Đồng Khởi': 'Đồng Khởi',
      'Đi về hướng đông bắc trên Lê Lợi về phía Pasteur': 'Lê Lợi',
      'Tại vòng xuyến, đi theo lối ra thứ 2 vào Đồng Khởi': 'Đồng Khởi',
      'Rẽ trái vào Nam Kỳ Khởi Nghĩa theo hướng Quận 3': 'Nam Kỳ Khởi Nghĩa',
    };
    for (final MapEntry(key: text, value: name) in cases.entries) {
      expect(roadNameOf(text), name, reason: text);
    }
  });

  test('tags are stripped and only the first line is read', () {
    expect(roadNameOf('Turn <b>left</b> onto <b>Nguyễn Huệ</b>'), 'Nguyễn Huệ');
    expect(
      roadNameOf(
        'Turn right onto Công xã Paris\nDestination will be on the left',
      ),
      'Công xã Paris',
    );
    expect(
      roadNameOf('Rẽ phải vào Lý Tự Trọng<div>Đường có thu phí</div>'),
      'Lý Tự Trọng',
    );
  });

  test('none: null', () {
    for (final text in [
      '',
      'Turn left',
      'Slight right toward Bến Thành',
      'Chếch sang trái',
      'Rẽ phải',
      'Destination will be on the right',
      'Điểm đến sẽ ở bên trái',
      'Turn left onto',
      '<b></b>',
    ]) {
      expect(roadNameOf(text), isNull, reason: text);
    }
  });
}
