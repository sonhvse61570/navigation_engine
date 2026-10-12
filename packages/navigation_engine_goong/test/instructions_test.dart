// Runs on the VM, and on node with `dart test -p node -t js` (see
// dart_test.yaml): under dart2js the regular expressions are JavaScript's,
// whose unicode and case-insensitive matching (of "vào", "Đ"…) must agree.
@Tags(['js'])
library;

import 'package:navigation_engine_goong/src/instructions.dart';
import 'package:test/test.dart';

void main() {
  group('instructionText', () {
    test('strips the tags and decodes the entities', () {
      expect(
        instructionText('Turn <b>left</b> onto <B>Ng&#245; 5 &amp; 7</B>'),
        'Turn left onto Ngõ 5 & 7',
      );
      expect(
        instructionText('&lt;b&gt; &quot;A&quot; &#39;B&#39; &apos;C&apos;'),
        '<b> "A" \'B\' \'C\'',
      );
      expect(instructionText('Đ&#x1EA1;i&nbsp;lộ &#X1EA1;'), 'Đại lộ ạ');
      // An entity it does not know, or a bad one, is kept as it is.
      expect(
        instructionText('A &copy; &#xZZ; &#99999999; B'),
        'A &copy; &#xZZ; &#99999999; B',
      );
    });

    test(
      'a block tag (div, br, p) starts a new line; spaces are collapsed',
      () {
        expect(
          instructionText(
            'Turn <b>left</b>  onto <b>Nguyễn Trãi</b>'
            '<div style="font-size:0.9em">Destination   will be on the right'
            '</div>',
          ),
          'Turn left onto Nguyễn Trãi\nDestination will be on the right',
        );
        expect(instructionText(' A<br/>B<br>  <p>C</p> '), 'A\nB\nC');
        expect(instructionText(''), '');
      },
    );
  });

  group('roadNameOf', () {
    const cases = {
      // Google's English, with <b> tags: the segment after "onto" or "on".
      'Turn <b>right</b> onto <b>Phạm Văn Đồng</b>': 'Phạm Văn Đồng',
      'Head <b>south</b> on <b>Trần Cung</b>': 'Trần Cung',
      'Head <b>north</b> on <b>Láng</b> toward <b>Chùa Láng</b>': 'Láng',
      'Slight <b>right</b> to stay on <b>Xuân Thủy</b>': 'Xuân Thủy',
      'Keep <b>left</b> to stay on <b>Xu&#226;n Tảo</b>': 'Xuân Tảo',
      'At the roundabout, take the <b>2nd</b> exit onto <b>Kim Mã</b>':
          'Kim Mã',
      'Continue onto <b>QL1A</b>/<b>AH1</b>': 'QL1A',
      'Turn <b>left</b> onto <b>Ng&#245; 5 &amp; 7</b>': 'Ngõ 5 & 7',
      // A note in a <div> is not part of the name.
      'Turn <b>left</b> onto <b>Nguyễn Trãi</b>'
              '<div style="font-size:0.9em">Destination will be on the right'
              '</div>':
          'Nguyễn Trãi',
      // No road.
      'Turn <b>left</b>': '',
      'Head <b>south</b>': '',
      // A road that is not bold.
      'Turn <b>left</b> onto Main Street': 'Main Street',
      // Goong's plain Vietnamese.
      'Rẽ trái vào Hoàng Quốc Việt': 'Hoàng Quốc Việt',
      'Bắt đầu đi từ Trần Cung': 'Trần Cung',
      'Tiếp tục đi trên Đường Láng': 'Đường Láng',
      'Đi theo Xuân Thủy': 'Xuân Thủy',
      'Đi theo hướng Bắc trên Trần Cung': 'Trần Cung',
      'Tại vòng xuyến, đi theo lối ra thứ 2 vào Nguyễn Văn Huyên':
          'Nguyễn Văn Huyên',
      'Rẽ trái vào Hoàng Quốc Việt, rồi đi thẳng': 'Hoàng Quốc Việt',
      'Rẽ phải vào Đ. Láng.': 'Đ. Láng',
      'Rẽ <b>trái</b> vào <b>Hoàng Quốc Việt</b>': 'Hoàng Quốc Việt',
      // The name stops before a phrase that says where the road leads.
      'Rẽ phải vào Trần Duy Hưng theo hướng Big C': 'Trần Duy Hưng',
      'Tiếp tục vào Đường Láng rồi rẽ phải': 'Đường Láng',
      'Đi theo Xuân Thủy hướng về Cầu Giấy': 'Xuân Thủy',
      'Đi trên Kim Mã về hướng Nguyễn Thái Học': 'Kim Mã',
      'Tiếp tục đi trên Đường Láng theo hướng Cầu Giấy': 'Đường Láng',
      'Turn left onto Main St toward Elm St': 'Main St',
      'Head north on Main St towards the river': 'Main St',
      // "theo hướng" is a direction, not a road.
      'Đi theo hướng Bắc': '',
      'Rẽ phải': '',
      'Hướng sang phải': '',
      'Bạn đã đến điểm đích': '',
      // A keyword inside a word is not one.
      'Đi thẳng qua Ontop': '',
      '': '',
    };
    for (final MapEntry(key: html, value: name) in cases.entries) {
      test('"$html"', () => expect(roadNameOf(html), name));
    }
  });
}
