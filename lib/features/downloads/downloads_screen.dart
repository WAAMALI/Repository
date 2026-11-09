import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/download/download_task_service.dart';
import '../../core/download/range_download_engine.dart';
import '../../core/services/download_bridge.dart';
import '../../core/services/license_service.dart';
import '../player/player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<NativeDownload> _external = const [];
  List<DownloadTask> _internal = const [];
  StreamSubscription<List<DownloadTask>>? _subscription;
  Timer? _poller;
  bool _loading = true;
  int _maxConcurrent = 2;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _internal = DownloadTaskService.instance.tasks;
    DownloadTaskService.instance.restore();
    DownloadTaskService.instance.setMaxConcurrent(_maxConcurrent);
    _subscription = DownloadTaskService.instance.changes.listen((items) {
      if (mounted) setState(() => _internal = items);
    });
    _refreshExternal();
    _poller = Timer.periodic(const Duration(seconds: 4), (_) => _refreshExternal(silent: true));
  }

  Future<void> _refreshExternal({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final items = await DownloadBridge.instance.queryAll();
      if (mounted) setState(() { _external = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addInternal() async {
    try {
      await LicenseService.instance.ensureValid();
    } on LicenseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }
    final url = TextEditingController();
    final name = TextEditingController();
    var connections = 4;
    final accepted = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('إضافة تحميل داخلي'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: url, decoration: const InputDecoration(labelText: 'رابط الملف HTTP/HTTPS')),
          const SizedBox(height: 10),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الملف مع الامتداد')),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: connections,
            decoration: const InputDecoration(labelText: 'عدد الاتصالات'),
            items: [1,2,3,4,5,6,7,8].map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
            onChanged: (v) => setDialog(() => connections = v ?? 4),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بدء التحميل')),
        ],
      ),
    ));
    if (accepted == true) {
      try {
        await DownloadTaskService.instance.add(url: url.text, fileName: name.text, connections: connections);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
    url.dispose(); name.dispose();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes/1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes/(1024*1024)).toStringAsFixed(1)} MB';
    return '${(bytes/(1024*1024*1024)).toStringAsFixed(2)} GB';
  }

  String _taskStatus(DownloadTask t) => switch (t.state) {
    DownloadState.queued => 'في قائمة الانتظار',
    DownloadState.probing => 'فحص السيرفر',
    DownloadState.downloading => 'جارٍ التحميل',
    DownloadState.paused => 'متوقف مؤقتًا',
    DownloadState.completed => 'اكتمل',
    DownloadState.failed => 'فشل: ${t.error ?? ''}',
  };

  String _nativeStatus(NativeDownload item) {
    if (item.isComplete) return 'اكتمل';
    if (item.isFailed) return 'فشل (${item.reason})';
    if (item.isRunning) return 'جارٍ التحميل';
    if (item.isPending) return 'في الانتظار';
    if (item.isPaused) return 'متوقف مؤقتًا بواسطة النظام';
    return 'قيد المعالجة';
  }

  @override
  void dispose() {
    _tabs.dispose(); _subscription?.cancel(); _poller?.cancel(); super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('التحميلات'),
      bottom: TabBar(controller: _tabs, tabs: const [
        Tab(text: 'التحميل الداخلي'),
        Tab(text: 'مدير خارجي'),
      ]),
      actions: [
        PopupMenuButton<int>(
          tooltip: 'عدد التنزيلات المتزامنة',
          icon: const Icon(Icons.tune),
          initialValue: _maxConcurrent,
          onSelected: (value) {
            setState(() => _maxConcurrent = value);
            DownloadTaskService.instance.setMaxConcurrent(value);
          },
          itemBuilder: (_) => [1,2,3,4].map((n) => PopupMenuItem(
            value: n, child: Text('تنزيلات متزامنة: $n'))).toList(),
        ),
        IconButton(onPressed: _refreshExternal, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
      ],
    ),
    floatingActionButton: AnimatedBuilder(
      animation: _tabs,
      builder: (_, __) => _tabs.index == 0
        ? FloatingActionButton.extended(onPressed: _addInternal, icon: const Icon(Icons.add), label: const Text('إضافة تحميل'))
        : const SizedBox.shrink(),
    ),
    body: TabBarView(controller: _tabs, children: [
      _internalList(),
      _externalList(),
    ]),
  );

  Widget _internalList() {
    if (_internal.isEmpty) return const Center(child: Text('لا توجد تنزيلات داخلية بعد'));
    return ListView.separated(
      padding: const EdgeInsets.all(12), itemCount: _internal.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final t = _internal[i];
        return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.download_for_offline_outlined),
              const SizedBox(width: 8),
              Expanded(child: Text(t.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              PopupMenuButton<int>(
                tooltip: 'أولوية التنزيل',
                onSelected: (v) => DownloadTaskService.instance.setPriority(t.id, v),
                itemBuilder: (_) => [0,1,2,3,4,5].map((v) => PopupMenuItem(
                  value: v, child: Text('الأولوية $v'))).toList(),
                child: Padding(padding: const EdgeInsets.all(8), child: Text('P${t.priority}')),
              ),
              if (t.state == DownloadState.completed && t.localPath != null)
                IconButton(
                  tooltip: 'تشغيل دون إنترنت',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                    PlayerScreen(title: t.fileName, url: t.localPath!, mediaId: t.id,
                      section: 'offline', isLocalFile: true))),
                  icon: const Icon(Icons.play_circle_outline),
                ),
              if (t.state == DownloadState.downloading || t.state == DownloadState.probing)
                IconButton(tooltip: 'إيقاف', onPressed: () => DownloadTaskService.instance.pause(t.id), icon: const Icon(Icons.pause_circle_outline)),
              if (t.state == DownloadState.paused || t.state == DownloadState.failed)
                IconButton(
                  tooltip: 'استئناف',
                  onPressed: () async {
                    try {
                      await LicenseService.instance.ensureValid();
                      await DownloadTaskService.instance.resume(t.id);
                    } on LicenseException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.message)),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.play_circle_outline),
                ),
              IconButton(tooltip: 'إزالة', onPressed: () => DownloadTaskService.instance.remove(t.id), icon: const Icon(Icons.delete_outline)),
            ]),
            Text(_taskStatus(t), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: t.totalBytes > 0 ? t.progress : null),
            const SizedBox(height: 5),
            Text('${(t.progress*100).toStringAsFixed(0)}% · ${_formatSize(t.receivedBytes)} / ${_formatSize(t.totalBytes)}',
              style: Theme.of(context).textTheme.labelSmall),
            if (t.localPath != null) SelectableText(t.localPath!, style: Theme.of(context).textTheme.labelSmall),
          ],
        )));
      },
    );
  }

  Widget _externalList() {
    if (_loading && _external.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_external.isEmpty) return const Center(child: Text('لا توجد تنزيلات عبر المدير الخارجي'));
    return ListView.separated(
      padding: const EdgeInsets.all(12), itemCount: _external.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final item = _external[i];
        return Card(child: ListTile(
          title: Text(item.title ?? 'تنزيل ${item.id}'),
          subtitle: Text('${_nativeStatus(item)} · ${_formatSize(item.downloaded)} / ${_formatSize(item.total)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (item.isComplete && (item.contentUri ?? item.localUri) != null)
              IconButton(tooltip: 'تشغيل دون إنترنت', onPressed: () {
                final uri = item.contentUri ?? item.localUri!;
                Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                  PlayerScreen(title: item.title ?? 'فيديو محمّل', url: uri, mediaId: 'offline-${item.id}', section: 'offline')));
              }, icon: const Icon(Icons.play_circle_outline)),
            IconButton(tooltip: 'إلغاء', onPressed: () async {
              await DownloadBridge.instance.remove(item.id); await _refreshExternal();
            }, icon: const Icon(Icons.delete_outline)),
          ]),
        ));
      },
    );
  }
}
