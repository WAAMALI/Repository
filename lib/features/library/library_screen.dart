import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import '../player/player_screen.dart';
import '../../core/services/app_database.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Future<List<Map<String, Object?>>>? _favorites;
  Future<List<Map<String, Object?>>>? _history;
  Future<List<Map<String, Object?>>>? _offline;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab.clamp(0, 2).toInt());
    _reload();
  }

  void _reload() {
    _favorites = AppDatabase.instance.favorites();
    _history = AppDatabase.instance.history();
    _offline = AppDatabase.instance.offlineFiles();
  }

  Future<void> _removeFavorite(String id) async {
    await AppDatabase.instance.setFavorite(id: id, name: '', section: '', favorite: false);
    if (mounted) setState(_reload);
  }

  Future<void> _removeHistory(String id) async {
    await AppDatabase.instance.removeHistory(id);
    if (mounted) setState(_reload);
  }

  Future<void> _clearHistory() async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('مسح سجل المشاهدة؟'),
      content: const Text('سيتم حذف سجل المشاهدة المحلي من هذا الجهاز.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
      ],
    ));
    if (yes == true) {
      await AppDatabase.instance.clearHistory();
      if (mounted) setState(_reload);
    }
  }


  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _deleteOffline(Map<String, Object?> row) async {
    final id = '${row['media_id']}';
    final path = '${row['file_path']}';
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('حذف الملف المحمّل؟'),
      content: const Text('سيتم حذف الملف وبياناته من مكتبة هذا الجهاز.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
      ],
    ));
    if (yes != true) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.parent.delete(recursive: true);
      await AppDatabase.instance.removeOfflineFile(id);
      if (mounted) setState(_reload);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الملف: $e')));
    }
  }

  Widget _offlineRows(Future<List<Map<String, Object?>>> future) =>
    FutureBuilder<List<Map<String, Object?>>>(future: future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('تعذر تحميل الملفات: ${snapshot.error}'));
      final rows = snapshot.data ?? const [];
      if (rows.isEmpty) return const Center(child: Text('لا توجد ملفات محفوظة للمشاهدة دون إنترنت'));
      final total = rows.fold<int>(0, (sum, row) => sum + ((row['file_size'] as num?)?.toInt() ?? 0));
      return Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          const Icon(Icons.storage_outlined),
          const SizedBox(width: 8),
          Text('المساحة المستخدمة: ${_size(total)}'),
          const Spacer(),
          Text('${rows.length} ملف'),
        ])),
        Expanded(child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, index) {
            final row = rows[index];
            final id = '${row['media_id']}';
            final name = '${row['name'] ?? 'ملف محمّل'}';
            final path = '${row['file_path']}';
            final size = (row['file_size'] as num?)?.toInt() ?? 0;
            final exists = File(path).existsSync();
            return Card(child: ListTile(
              leading: Icon(exists ? Icons.movie_outlined : Icons.warning_amber_outlined),
              title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(exists ? '${_size(size)} · ${row['section']}' : 'الملف غير موجود على الجهاز'),
              onTap: exists ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                PlayerScreen(title: name, url: path, mediaId: id, section: 'offline', isLocalFile: true))) : null,
              trailing: IconButton(tooltip: 'حذف الملف', onPressed: () => _deleteOffline(row),
                icon: const Icon(Icons.delete_outline)),
            ));
          },
        )),
      ]);
    });

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('مكتبتي'),
      bottom: TabBar(controller: _tabs, tabs: const [
        Tab(icon: Icon(Icons.favorite_outline), text: 'المفضلة'),
        Tab(icon: Icon(Icons.history), text: 'سجل المشاهدة'),
      ]),
      actions: [
        IconButton(tooltip: 'تحديث', onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'مسح السجل', onPressed: _clearHistory, icon: const Icon(Icons.delete_sweep_outlined)),
      ],
    ),
    body: TabBarView(controller: _tabs, children: [
      _rows(_favorites!, empty: 'لم تضف أي محتوى إلى المفضلة بعد', onRemove: _removeFavorite, history: false),
      _rows(_history!, empty: 'لا يوجد سجل مشاهدة حتى الآن', onRemove: _removeHistory, history: true),
      _offlineRows(_offline!),
    ]),
  );

  Widget _rows(Future<List<Map<String, Object?>>> future, {
    required String empty,
    required Future<void> Function(String) onRemove,
    required bool history,
  }) => FutureBuilder<List<Map<String, Object?>>>(future: future, builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
    if (snapshot.hasError) return Center(child: Text('تعذر تحميل البيانات: ${snapshot.error}'));
    final rows = snapshot.data ?? const [];
    if (rows.isEmpty) return Center(child: Text(empty));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final row = rows[index];
        final id = '${row['media_id'] ?? ''}';
        final name = '${row['name'] ?? 'بدون اسم'}';
        final image = row['image']?.toString();
        final section = '${row['section'] ?? ''}';
        final position = (row['position_ms'] as num?)?.toInt() ?? 0;
        final duration = (row['duration_ms'] as num?)?.toInt() ?? 0;
        final progress = duration > 0 ? (position / duration).clamp(0.0, 1.0).toDouble() : 0.0;
        return Card(child: ListTile(
          leading: SizedBox(width: 54, height: 72, child: image == null || image.isEmpty
            ? const Icon(Icons.movie_outlined, size: 32)
            : CachedNetworkImage(imageUrl: image, fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image_outlined))),
          title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(section),
            if (history && duration > 0) ...[
              const SizedBox(height: 5),
              LinearProgressIndicator(value: progress),
              Text('آخر موضع: ${Duration(milliseconds: position).inMinutes} دقيقة'),
            ],
          ]),
          trailing: IconButton(
            tooltip: 'إزالة',
            onPressed: () => onRemove(id),
            icon: const Icon(Icons.delete_outline),
          ),
        ));
      },
    );
  });
}
