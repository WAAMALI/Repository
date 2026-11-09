import 'package:flutter/material.dart';
import '../../core/models/iptv_models.dart';
import '../../core/services/session_store.dart';
import '../../core/services/xtream_client.dart';
import 'media_browser.dart';
import 'epg_screen.dart';
import '../library/library_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.onSignOut, required this.onThemeChanged});
  final VoidCallback onSignOut;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  XtreamClient? _client;
  CatalogSection _section = CatalogSection.live;
  bool _dark = true;

  @override
  void initState() {
    super.initState();
    _loadClient();
  }

  Future<void> _loadClient() async {
    final credentials = await SessionStore.instance.read();
    if (!mounted) return;
    if (credentials == null) { widget.onSignOut(); return; }
    setState(() => _client = XtreamClient(credentials));
  }

  @override
  void dispose() { _client?.close(); super.dispose(); }

  void _select(CatalogSection section) => setState(() => _section = section);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isTvOrWide = width >= 800;
    final destinations = <(CatalogSection, String, IconData)>[
      (CatalogSection.live, 'البث المباشر', Icons.live_tv_outlined),
      (CatalogSection.movies, 'الأفلام', Icons.movie_outlined),
      (CatalogSection.series, 'المسلسلات', Icons.video_library_outlined),
      (CatalogSection.downloads, 'التحميلات', Icons.download_for_offline_outlined),
    ];
    final selectedIndex = destinations.indexWhere((d) => d.$1 == _section);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TVEXP IPTV', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'مكتبتي', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LibraryScreen())), icon: const Icon(Icons.video_library_outlined)),
          IconButton(tooltip: 'دليل البرامج EPG', onPressed: () { if (_client != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => EpgScreen(client: _client!))); }, icon: const Icon(Icons.calendar_month_outlined)),
          IconButton(tooltip: _dark ? 'الوضع الفاتح' : 'الوضع الداكن', onPressed: () { _dark = !_dark; widget.onThemeChanged(_dark ? ThemeMode.dark : ThemeMode.light); setState(() {}); }, icon: Icon(_dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined)),
          IconButton(tooltip: 'تسجيل الخروج', onPressed: widget.onSignOut, icon: const Icon(Icons.logout)),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(children: [
        if (isTvOrWide) NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (i) => _select(destinations[i].$1),
          labelType: NavigationRailLabelType.all,
          destinations: destinations.map((d) => NavigationRailDestination(icon: Icon(d.$3), label: Text(d.$2))).toList(),
        ),
        Expanded(child: _client == null ? const Center(child: CircularProgressIndicator()) : MediaBrowser(client: _client!, section: _section)),
      ]),
      bottomNavigationBar: isTvOrWide ? null : NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => _select(destinations[i].$1),
        destinations: destinations.map((d) => NavigationDestination(icon: Icon(d.$3), label: d.$2)).toList(),
      ),
    );
  }
}
