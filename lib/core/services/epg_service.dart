import 'package:xml/xml.dart';
import '../models/epg_program.dart';

class EpgService {
  const EpgService._();

  static List<EpgProgram> parseXmlTv(String source, {String? channelId}) {
    final document = XmlDocument.parse(source);
    final result = <EpgProgram>[];
    for (final node in document.findAllElements('programme')) {
      final id = node.getAttribute('channel') ?? '';
      if (channelId != null && id != channelId) continue;
      final start = _xmlTvDate(node.getAttribute('start'));
      final stop = _xmlTvDate(node.getAttribute('stop'));
      if (start == null || stop == null || !stop.isAfter(start)) continue;
      result.add(EpgProgram(
        title: node.getElement('title')?.innerText.trim() ?? 'برنامج بدون عنوان',
        description: node.getElement('desc')?.innerText.trim() ?? '',
        start: start,
        end: stop,
        channelId: id,
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static DateTime? _xmlTvDate(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?(?:\s*([+-])(\d{2})(\d{2}))?').firstMatch(value.trim());
    if (match == null) return DateTime.tryParse(value);
    final second = int.tryParse(match.group(6) ?? '0') ?? 0;
    var date = DateTime.utc(
      int.parse(match.group(1)!), int.parse(match.group(2)!), int.parse(match.group(3)!),
      int.parse(match.group(4)!), int.parse(match.group(5)!), second,
    );
    final sign = match.group(7);
    if (sign != null) {
      final offset = Duration(hours: int.parse(match.group(8)!), minutes: int.parse(match.group(9)!));
      date = sign == '+' ? date.subtract(offset) : date.add(offset);
    }
    return date.toLocal();
  }
}
