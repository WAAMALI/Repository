import 'package:flutter/material.dart';
import '../../core/models/epg_program.dart';
import '../../core/models/iptv_models.dart';
import '../../core/services/xtream_client.dart';

class EpgScreen extends StatefulWidget {
  const EpgScreen({super.key, required this.client});
  final XtreamClient client;
  @override
  State<EpgScreen> createState() => _EpgScreenState();
}

class _EpgScreenState extends State<EpgScreen> {
  late Future<List<MediaItem>> _channels;
  MediaItem? _selected;
  Future<List<EpgProgram>>? _programs;

  @override
  void initState() {
    super.initState();
    _channels = widget.client.items(CatalogSection.live);
  }

  void _select(MediaItem? channel) {
    setState(() {
      _selected = channel;
      _programs = channel == null ? null : widget.client.shortEpg(channel.id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دليل البرامج EPG')),
    body: FutureBuilder<List<MediaItem>>(
      future: _channels,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('تعذر تحميل القنوات: ${snapshot.error}'));
        final channels = snapshot.data ?? [];
        if (channels.isEmpty) return const Center(child: Text('لا توجد قنوات متاحة'));
        _selected ??= channels.first;
        _programs ??= widget.client.shortEpg(_selected!.id);
        final wide = MediaQuery.sizeOf(context).width >= 800;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<MediaItem>(
              value: _selected,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'اختر القناة', prefixIcon: Icon(Icons.live_tv)),
              items: channels.map((c) => DropdownMenuItem(value: c, child: Text(c.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: _select,
            ),
            const SizedBox(height: 16),
            Expanded(child: FutureBuilder<List<EpgProgram>>(
              future: _programs,
              builder: (context, epg) {
                if (epg.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (epg.hasError) return Center(child: Text('تعذر تحميل دليل البرامج: ${epg.error}'));
                final rows = epg.data ?? [];
                if (rows.isEmpty) return const Center(child: Text('لا يوفر السيرفر دليل برامج لهذه القناة'));
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _ProgramCard(program: rows[index], wide: wide),
                );
              },
            )),
          ]),
        );
      },
    ),
  );
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program, required this.wide});
  final EpgProgram program;
  final bool wide;
  String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final active = program.isNow;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: wide ? 110 : 76, child: Column(children: [
            Text(_time(program.start), style: const TextStyle(fontWeight: FontWeight.bold)),
            const Icon(Icons.arrow_downward, size: 16),
            Text(_time(program.end)),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(program.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (active) const Chip(label: Text('يعرض الآن'), visualDensity: VisualDensity.compact),
            ]),
            if (program.description.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(program.description, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
            if (active) Padding(padding: const EdgeInsets.only(top: 10), child: LinearProgressIndicator(value: program.progress)),
          ])),
        ]),
      ),
    );
  }
}
