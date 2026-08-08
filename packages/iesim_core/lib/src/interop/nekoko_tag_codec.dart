/// NekokoLPA2 nickname 中的结构化标签。
sealed class NekokoTag {
  const NekokoTag();
}

class NekokoTextTag extends NekokoTag {
  final String value;

  NekokoTextTag(this.value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'value', '标签不能为空');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NekokoTextTag && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class NekokoDateTag extends NekokoTag {
  /// 仅年月日有意义，以 UTC 零点保存。
  final DateTime date;
  final String? note;

  NekokoDateTag({required this.date, this.note}) {
    if (!date.isUtc ||
        date.hour != 0 ||
        date.minute != 0 ||
        date.second != 0 ||
        date.millisecond != 0 ||
        date.microsecond != 0) {
      throw ArgumentError.value(date, 'date', '必须是 UTC 日历日零点');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is NekokoDateTag && other.date == date && other.note == note;

  @override
  int get hashCode => Object.hash(date, note);
}

class NekokoDecodeResult {
  final List<NekokoTag> tags;
  final List<String> issues;

  NekokoDecodeResult({
    required List<NekokoTag> tags,
    required List<String> issues,
  }) : tags = List.unmodifiable(tags),
       issues = List.unmodifiable(issues);
}

/// NekokoLPA2 profile nickname 标签编解码。
///
/// 空格、冒号分别按协议转义为 0x11、0x03，标签以 0x0A 分隔。
/// 畸形片段只进入 [NekokoDecodeResult.issues]，不会使整条 nickname 崩溃。
abstract final class NekokoTagCodec {
  static const _escapedSpace = '\x11';
  static const _escapedColon = '\x03';
  static const _separator = '\x0A';

  static final RegExp _tagPattern = RegExp(r'(?:^|[\s\x0A])([td]:[^\s\x0A]+)');

  static String encode(Iterable<NekokoTag> tags) =>
      tags.map(_encodeTag).join(_separator);

  /// 替换 nickname 中已有的 t:/d: 标签，并保留普通昵称文本。
  static String replaceTags(String nickname, Iterable<NekokoTag> tags) {
    final plain = nickname
        .replaceAll(_tagPattern, ' ')
        .replaceAll(RegExp(r'[\s\x0A]+'), ' ')
        .trim();
    final encoded = encode(tags);
    if (plain.isEmpty) return encoded;
    if (encoded.isEmpty) return plain;
    return '$plain$_separator$encoded';
  }

  static NekokoDecodeResult decode(String nickname) {
    final tags = <NekokoTag>[];
    final issues = <String>[];
    for (final match in _tagPattern.allMatches(nickname)) {
      final token = match.group(1)!;
      if (token.startsWith('t:')) {
        final value = _unescape(token.substring(2)).trim();
        if (value.isEmpty) {
          issues.add('空文本标签已忽略');
        } else {
          tags.add(NekokoTextTag(value));
        }
        continue;
      }
      final body = token.substring(2);
      final separator = body.indexOf(':');
      final dateText = separator < 0 ? body : body.substring(0, separator);
      final noteText = separator < 0 ? null : body.substring(separator + 1);
      final date = _parseDate(dateText);
      if (date == null) {
        issues.add('无效日期标签“$token”已忽略');
        continue;
      }
      final decodedNote = noteText == null ? null : _unescape(noteText).trim();
      tags.add(
        NekokoDateTag(
          date: date,
          note: decodedNote == null || decodedNote.isEmpty ? null : decodedNote,
        ),
      );
    }
    return NekokoDecodeResult(tags: tags, issues: issues);
  }

  static String _encodeTag(NekokoTag tag) => switch (tag) {
    NekokoTextTag(value: final value) => 't:${_escape(value)}',
    NekokoDateTag(date: final date, note: final note) =>
      'd:${_dateText(date)}${note == null ? '' : ':${_escape(note)}'}',
  };

  static String _escape(String value) => value
      .replaceAll(':', _escapedColon)
      .replaceAll(RegExp(r'\s'), _escapedSpace);

  static String _unescape(String value) =>
      value.replaceAll(_escapedSpace, ' ').replaceAll(_escapedColon, ':');

  static String _dateText(DateTime date) {
    final year = date.year >= 2000 && date.year <= 2099
        ? (date.year % 100).toString().padLeft(2, '0')
        : date.year.toString().padLeft(4, '0');
    return '$year${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDate(String value) {
    if (!RegExp(r'^(\d{6}|\d{8})$').hasMatch(value)) return null;
    final yearDigits = value.length == 6 ? 2 : 4;
    final rawYear = int.parse(value.substring(0, yearDigits));
    final year = yearDigits == 2 ? 2000 + rawYear : rawYear;
    final month = int.parse(value.substring(yearDigits, yearDigits + 2));
    final day = int.parse(value.substring(yearDigits + 2));
    final date = DateTime.utc(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }
}
