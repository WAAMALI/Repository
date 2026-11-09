class EpgProgram {
  const EpgProgram({required this.title, required this.start, required this.end, this.description = '', this.channelId = ''});
  final String title;
  final DateTime start;
  final DateTime end;
  final String description;
  final String channelId;

  bool get isNow {
    final now = DateTime.now();
    return !now.isBefore(start) && now.isBefore(end);
  }

  double get progress {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 0;
    return (DateTime.now().difference(start).inMilliseconds / total).clamp(0.0, 1.0).toDouble();
  }

  factory EpgProgram.fromXtream(Map<String, dynamic> json) {
    DateTime parse(dynamic value) {
      if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt() * 1000);
      final text = (value ?? '').toString().trim();
      final numeric = int.tryParse(text);
      if (numeric != null) return DateTime.fromMillisecondsSinceEpoch(numeric * 1000);
      return DateTime.tryParse(text) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return EpgProgram(
      title: (json['title'] ?? json['name'] ?? 'برنامج بدون عنوان').toString(),
      start: parse(json['start_timestamp'] ?? json['start']),
      end: parse(json['stop_timestamp'] ?? json['end']),
      description: (json['description'] ?? json['desc'] ?? '').toString(),
      channelId: (json['channel_id'] ?? '').toString(),
    );
  }
}
