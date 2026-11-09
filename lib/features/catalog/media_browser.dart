import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/models/iptv_models.dart';
import '../../core/services/xtream_client.dart';
import '../../core/services/download_bridge.dart';
import '../../core/download/download_task_service.dart';
import '../../core/services/app_database.dart';
import '../../core/services/license_service.dart';
import '../downloads/downloads_screen.dart';
import '../player/player_screen.dart';

class MediaBrowser extends StatefulWidget {
  const MediaBrowser({super.key, required this.client, required this.section});
  final XtreamClient client;
  final CatalogSection section;
  @override
  State<MediaBrowser> createState() => _MediaBrowserState();
}

class _MediaBrowserState extends State<MediaBrowser> {
  late Future<List<MediaItem>> _items;
  Future<List<MediaCategory>>? _categories;
  String? _category;
  String _search = '';

  @override
  void initState() { super.initState(); _reload(); }
  @override
  void didUpdateWidget(covariant MediaBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) { _category = null; _search = ''; _reload(); }
  }

  void _reload() {
    if (widget.section == CatalogSection.downloads) return;
    _categories = widget.client.categories(widget.section);
    _items = widget.client.items(widget.section, categoryId: _category);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.section == CatalogSection.downloads) return const DownloadsScreen();
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1500 ? 8 : width >= 1200 ? 7 : width >= 900 ? 6 : width >= 700 ? 5 : width >= 520 ? 4 : 2;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Expanded(child: TextField(decoration: const InputDecoration(hintText: 'ابحث في المحتوى...', prefixIcon: Icon(Icons.search), isDense: true), onChanged: (v) => setState(() => _search = v.trim().toLowerCase()))),
          const SizedBox(width: 10),
          IconButton(tooltip: 'تحديث المحتوى', onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
        ]),
      ),
      SizedBox(height: 48, child: FutureBuilder<List<MediaCategory>>(
        future: _categories,
        builder: (context, snapshot) {
          final categories = snapshot.data ?? [];
          return ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: const Text('الكل'), selected: _category == null, onSelected: (_) { setState(() { _category = null; _reload(); }); })),
            ...categories.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(c.name), selected: _category == c.id, onSelected: (_) { setState(() { _category = c.id; _reload(); }); }))),
          ]);
        },
      )),
      Expanded(child: FocusTraversalGroup(child: FutureBuilder<List<MediaItem>>(
        future: _items,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _Message(message: snapshot.error.toString(), onRetry: () => setState(_reload));
          final items = (snapshot.data ?? []).where((e) => e.name.toLowerCase().contains(_search)).toList();
          if (items.isEmpty) return const Center(child: Text('لا يوجد محتوى مطابق'));
          return GridView.builder(
            padding: EdgeInsets.all(width >= 900 ? 22 : 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              childAspectRatio: widget.section == CatalogSection.live
                  ? (width >= 900 ? 1.35 : 1.18)
                  : (width >= 900 ? .72 : .66),
              crossAxisSpacing: width >= 900 ? 16 : 10,
              mainAxisSpacing: width >= 900 ? 18 : 10,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _MediaCard(item: items[index], client: widget.client),
          );
        },
      ))),
    ]);
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({required this.item, required this.client});
  final MediaItem item;
  final XtreamClient client;

  String _downloadFileName({String? extension}) {
    final safeName = item.name.replaceAll(RegExp(r'[\\/:*?\"<>|]'), '_').trim();
    final ext = (extension ?? item.extension ?? (item.section == CatalogSection.live ? 'ts' : 'mp4'))
        .replaceFirst(RegExp(r'\.'), '');
    final alreadyHasExtension = RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(safeName);
    return alreadyHasExtension ? safeName : '$safeName.$ext';
  }

  Future<void> _download(BuildContext context, {required bool external}) async {
    final url = client.streamUrl(item);
    final fileName = _downloadFileName();
    try {
      await LicenseService.instance.ensureValid();
      if (external) {
        await DownloadBridge.instance.shareToExternalManager(url: url, fileName: fileName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('اختر مدير التحميل الخارجي من القائمة')));
        }
      } else {
        final id = await DownloadTaskService.instance.add(
          url: url, fileName: fileName, connections: 4,
          priority: item.section == CatalogSection.movies ? 2 : 1,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('أُضيف إلى التحميل الداخلي · رقم المهمة $id')));
        }
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر بدء التحميل: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = item.section == CatalogSection.live;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Focus(
        child: Builder(
          builder: (focusContext) {
            final focused = Focus.of(focusContext).hasFocus;
            return InkWell(
              autofocus: false,
              onTap: () async {
                try {
                  await LicenseService.instance.ensureValid();
                } on LicenseException catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.message)),
                    );
                  }
                  return;
                }
                if (!context.mounted) return;
                if (item.section == CatalogSection.series) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SeriesDetailsScreen(
                        item: item,
                        client: client,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlayerScreen(
                        title: item.name,
                        url: client.streamUrl(item),
                        mediaId: item.id,
                        section: item.section.name,
                        image: item.image,
                        isLive: live,
                      ),
                    ),
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: focused
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: item.image == null || item.image!.isEmpty
                          ? Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Icon(
                                live ? Icons.live_tv : Icons.movie,
                                size: 42,
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: item.image!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(7, 7, 7, 2),
                      child: Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (item.section != CatalogSection.series)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FutureBuilder<bool>(
                            future: AppDatabase.instance.isFavorite(item.id),
                            builder: (context, snapshot) => IconButton(
                              tooltip: snapshot.data == true
                                  ? 'إزالة من المفضلة'
                                  : 'إضافة للمفضلة',
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                final next = snapshot.data != true;
                                await AppDatabase.instance.setFavorite(
                                  id: item.id,
                                  name: item.name,
                                  section: item.section.name,
                                  image: item.image,
                                  favorite: next,
                                );
                                if (context.mounted) {
                                  (context as Element).markNeedsBuild();
                                }
                              },
                              icon: Icon(
                                snapshot.data == true
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: snapshot.data == true
                                    ? Colors.redAccent
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'تحميل داخلي',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _download(context, external: false),
                            icon: const Icon(
                              Icons.download,
                              color: Color(0xFF4FCB91),
                            ),
                          ),
                          IconButton(
                            tooltip: 'مدير تحميل خارجي',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _download(context, external: true),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SeriesDetailsScreen extends StatefulWidget {
  const SeriesDetailsScreen({super.key, required this.item, required this.client});
  final MediaItem item;
  final XtreamClient client;
  @override
  State<SeriesDetailsScreen> createState() => _SeriesDetailsScreenState();
}

class _SeriesDetailsScreenState extends State<SeriesDetailsScreen> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _future = widget.client.seriesInfo(widget.item.id); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item.name)),
    body: FutureBuilder<Map<String, dynamic>>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text(snapshot.error.toString()));
      final episodes = snapshot.data?['episodes'];
      final rows = <Map<String, dynamic>>[];
      if (episodes is Map) { for (final season in episodes.values) { if (season is List) rows.addAll(season.whereType<Map>().map((e) => Map<String, dynamic>.from(e))); } }
      if (rows.isEmpty) return const Center(child: Text('لا توجد حلقات متاحة'));
      return ListView.builder(itemCount: rows.length, itemBuilder: (context, i) {
        final episode = rows[i];
        final id = (episode['id'] ?? '').toString();
        final name = (episode['title'] ?? episode['episode_num'] ?? 'Episode ${i + 1}').toString();
        final ext = (episode['container_extension'] ?? 'mp4').toString();
        final media = MediaItem(id: id, name: name, section: CatalogSection.series, extension: ext, raw: episode);
        final safeEpisodeName = name.replaceAll(RegExp(r'[\\/:*?\"<>|]'), '_').trim();
        final fileName = RegExp(r'\.[A-Za-z0-9]{2,5}$').hasMatch(safeEpisodeName)
            ? safeEpisodeName : '$safeEpisodeName.$ext';
        Future<void> downloadEpisode({required bool external}) async {
          final url = widget.client.streamUrl(media);
          try {
            await LicenseService.instance.ensureValid();
            if (external) {
              await DownloadBridge.instance.shareToExternalManager(url: url, fileName: fileName);
            } else {
              final taskId = await DownloadTaskService.instance.add(
                url: url, fileName: fileName, connections: 4, priority: 3);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('أُضيفت الحلقة إلى التحميل الداخلي · $taskId')));
            }
          } catch (e) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تعذر تحميل الحلقة: $e')));
          }
        }
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.play_arrow)),
          title: Text(name),
          subtitle: Text('الحلقة ${episode['episode_num'] ?? i + 1}'),
          onTap: () async {
            try {
              await LicenseService.instance.ensureValid();
              if (!context.mounted) return;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) =>
                PlayerScreen(title: name, url: widget.client.streamUrl(media),
                  mediaId: id, section: 'series', image: widget.item.image)));
            } on LicenseException catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.message)),
                );
              }
            }
          },
          trailing: PopupMenuButton<String>(
            tooltip: 'تحميل الحلقة',
            onSelected: (method) => downloadEpisode(external: method == 'external'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'internal', child: ListTile(
                dense: true, leading: Icon(Icons.download), title: Text('تحميل داخلي'))),
              PopupMenuItem(value: 'external', child: ListTile(
                dense: true, leading: Icon(Icons.open_in_new), title: Text('مدير تحميل خارجي'))),
            ],
          ),
        );
      });
    }),
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))]));
}
