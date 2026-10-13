// Reading Google-style `html_instructions`: Goong sends plain Vietnamese
// ("Rẽ trái vào Hoàng Quốc Việt") or Google's HTML ("Turn <b>left</b> onto
// <b>Main St</b><div …>Toll road</div>"). Not exported.

/// [html] as plain text: the tags stripped (a `div`, `br` or `p` starts a
/// new line), the entities decoded, the spaces collapsed and each line
/// trimmed; empty lines are dropped.
String instructionText(String html) {
  final text = _decodeEntities(
    html.replaceAll(_blockTag, '\n').replaceAll(_tag, ''),
  );
  return [
    for (final line in text.split('\n'))
      if (line.replaceAll(_spaces, ' ').trim() case final l when l.isNotEmpty)
        l,
  ].join('\n');
}

/// The road a step's [html] instructions lead onto; empty when they name
/// none.
///
/// - With Google's tags, the `<b>` segment after "onto" or "on" (or the
///   Vietnamese "vào", "trên", "theo", "từ"): "Turn `<b>`left`</b>` onto
///   `<b>`Phạm Văn Đồng`</b>`" gives "Phạm Văn Đồng".
/// - Else, in the plain text, what follows the last of those words, up to a
///   comma, a semicolon, a phrase that says where the road leads ("theo
///   hướng", "về hướng", "hướng về", "hướng đến", "rồi", "toward") or the
///   end: "Rẽ trái vào Hoàng Quốc Việt" gives "Hoàng Quốc Việt"; "Rẽ phải
///   vào Trần Duy Hưng theo hướng Big C" gives "Trần Duy Hưng"; "Bắt đầu đi
///   từ Trần Cung" gives "Trần Cung". "theo hướng" itself is a direction,
///   not a road: "Đi theo hướng Bắc" names none.
///
/// The words that lead onto a road ("onto", "vào") win over the ones that
/// say where the vehicle already is ("on", "trên", "theo", "từ"). A `<div>`
/// (Google's notes, such as "Toll road") is ignored.
String roadNameOf(String html) {
  final main = html.replaceAll(_note, '\n');
  final tagged = _pick(_beforeBold.allMatches(main).toList());
  if (tagged != null) {
    final name = instructionText(tagged.group(2)!).replaceAll('\n', ' ');
    if (name.isNotEmpty) return name;
  }
  final text = instructionText(main);
  final keyword = _pick(_keyword.allMatches(text).toList());
  if (keyword == null) return '';
  var rest = text.substring(keyword.end);
  final end = rest.indexOf(_nameEnd);
  if (end >= 0) rest = rest.substring(0, end);
  // The name stops before a phrase that says where the road leads.
  final toward = _toward.firstMatch(rest);
  if (toward != null) rest = rest.substring(0, toward.start);
  return rest.trim().replaceFirst(_trailingDots, '').trim();
}

// "theo" followed by "hướng" ("theo hướng Bắc") is a direction.
const _keywords = r'(onto|on|vào|trên|theo(?!\s+hướng)|từ)';

/// The words that lead onto a road, rather than along one.
const _onto = {'onto', 'vào'};

/// The last match whose keyword leads onto a road, else the last match.
RegExpMatch? _pick(List<RegExpMatch> matches) {
  for (final m in matches.reversed) {
    if (_onto.contains(m.group(1)!.toLowerCase())) return m;
  }
  return matches.isEmpty ? null : matches.last;
}

final _beforeBold = RegExp(
  '(?:^|\\s)$_keywords\\s+<b>(.*?)</b>',
  caseSensitive: false,
  unicode: true,
  dotAll: true,
);
final _keyword = RegExp(
  '(?:^|\\s)$_keywords\\s+',
  caseSensitive: false,
  unicode: true,
);
final _note = RegExp(
  r'<div\b[^>]*>.*?</div>',
  caseSensitive: false,
  dotAll: true,
);
final _blockTag = RegExp(
  r'<\s*/?\s*(?:br|div|p)\b[^>]*>',
  caseSensitive: false,
);
final _tag = RegExp('<[^>]*>');
final _spaces = RegExp('[ \t ]+');
final _nameEnd = RegExp('[,;\n]');
final _toward = RegExp(
  r'\s(?:theo hướng|về hướng|hướng về|hướng đến|rồi|towards|toward)(?=\s|$)',
  caseSensitive: false,
  unicode: true,
);
final _trailingDots = RegExp(r'\.+$');
final _entity = RegExp('&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

const _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

/// [text] with its HTML entities decoded: the usual named ones and every
/// numeric one. An entity it does not know is kept as it is.
String _decodeEntities(String text) => text.replaceAllMapped(_entity, (m) {
  final name = m.group(1)!;
  if (!name.startsWith('#')) return _named[name] ?? m.group(0)!;
  final hex = name.length > 1 && (name[1] == 'x' || name[1] == 'X');
  final code = int.tryParse(
    hex ? name.substring(2) : name.substring(1),
    radix: hex ? 16 : 10,
  );
  if (code == null ||
      code > 0x10FFFF ||
      (code >= 0xD800 && code <= 0xDFFF) ||
      code == 0) {
    return m.group(0)!;
  }
  return String.fromCharCode(code);
});
