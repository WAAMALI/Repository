import 'package:flutter_test/flutter_test.dart';
import 'package:tvexp_iptv/core/models/epg_program.dart';
import 'package:tvexp_iptv/core/services/epg_service.dart';

void main() {
  test('parses Xtream EPG timestamps', () {
    final p = EpgProgram.fromXtream({'title': 'News', 'start_timestamp': 1793380000, 'stop_timestamp': 1793383600});
    expect(p.title, 'News');
    expect(p.end.isAfter(p.start), isTrue);
  });

  test('parses XMLTV programme entries and sorts them', () {
    const xml = '''<?xml version="1.0"?><tv><programme channel="c1" start="20261030180000 +0200" stop="20261030190000 +0200"><title>Evening News</title><desc>Daily news</desc></programme><programme channel="c1" start="20261030170000 +0200" stop="20261030180000 +0200"><title>Talk</title></programme></tv>''';
    final items = EpgService.parseXmlTv(xml, channelId: 'c1');
    expect(items.length, 2);
    expect(items.first.title, 'Talk');
    expect(EpgService.parseXmlTv(xml, channelId: 'other'), isEmpty);
  });
}
