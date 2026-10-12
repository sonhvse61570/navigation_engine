// Reading road names from Routes v2 `navigationInstruction.instructions`,
// best effort: Google gives no road name field. The text is plain ("Turn
// left onto Pasteur", "Rẽ trái vào Pasteur"), its later lines notes
// ("Destination will be on the left"). Not exported.

/// The road [instructions] lead onto, best effort; null when they name
/// none.
///
/// Only the first line is read, with any tags stripped. The name is what
/// follows the last keyword that leads onto a road (English "onto",
/// Vietnamese "vào", "sang" when not followed by a direction, "đi tiếp"),
/// else the last one that says where the vehicle is ("on", "trên"): "Turn
/// left onto Pasteur" gives "Pasteur", "Head north on Lê Lợi toward
/// Pasteur" gives "Lê Lợi", "Rẽ phải sang Hai Bà Trưng" gives "Hai Bà
/// Trưng". It stops at a comma, a semicolon or a phrase that says where the
/// road leads ("toward", "về phía", "theo hướng", …); trailing dots are
/// dropped. A side ("the left", "bên phải") is not a name.
String? roadNameOf(String instructions) {
  final line = instructions
      .replaceAll(_note, '\n')
      .replaceAll(_tag, '')
      .split('\n')
      .first
      .replaceAll(_spaces, ' ')
      .trim();
  final matches = _keyword.allMatches(line).toList();
  RegExpMatch? pick;
  for (final m in matches.reversed) {
    if (!_along.contains(m.group(1)!.toLowerCase())) {
      pick = m;
      break;
    }
  }
  pick ??= matches.isEmpty ? null : matches.last;
  if (pick == null) return null;
  var rest = line.substring(pick.end);
  final end = rest.indexOf(_nameEnd);
  if (end >= 0) rest = rest.substring(0, end);
  final toward = _toward.firstMatch(rest);
  if (toward != null) rest = rest.substring(0, toward.start);
  final name = rest.trim().replaceFirst(_trailingDots, '').trim();
  if (name.isEmpty || _sides.contains(name.toLowerCase())) return null;
  return name;
}

/// The keywords that say where the vehicle already is, rather than lead
/// onto a road.
const _along = {'on', 'trên'};

final _keyword = RegExp(
  // "đi tiếp trên X" (to stay on X) leads onto X as a whole.
  r'(?:^|\s)(onto|on|vào|sang(?!\s+(?:trái|phải|làn))|đi tiếp(?:\s+trên)?'
  r'|trên)(?=\s)',
  caseSensitive: false,
  unicode: true,
);
final _note = RegExp(
  r'<div\b[^>]*>.*?</div>',
  caseSensitive: false,
  dotAll: true,
);
final _tag = RegExp('<[^>]*>');
final _spaces = RegExp('[ \t ]+');
final _nameEnd = RegExp('[,;]');
final _toward = RegExp(
  r'\s(?:towards|toward|về phía|theo hướng|về hướng|hướng về|rồi)(?=\s|$)',
  caseSensitive: false,
  unicode: true,
);
final _trailingDots = RegExp(r'\.+$');
const _sides = {
  'the left',
  'the right',
  'your left',
  'your right',
  'bên trái',
  'bên phải',
};
