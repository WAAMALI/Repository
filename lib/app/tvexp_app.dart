import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/license_screen.dart';
import '../features/catalog/home_shell.dart';
import '../core/services/session_store.dart';
import '../core/services/license_service.dart';
import '../core/services/update_service.dart';

class TvexpApp extends StatefulWidget {
  const TvexpApp({super.key});
  @override
  State<TvexpApp> createState() => _TvexpAppState();
}

class _TvexpAppState extends State<TvexpApp> {
  bool _ready = false;
  bool _signedIn = false;
  bool _licensed = false;
  String? _licenseMessage;
  bool _updateCheckStarted = false;
  ThemeMode _themeMode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var licensed = false;
    dynamic restoreError;

    try {
      licensed = await LicenseService.instance.restoreAndValidate();
    } catch (error, stack) {
      restoreError = error;
      debugPrint('[TVEXP STARTUP] License restore failed: $error');
      debugPrintStack(stackTrace: stack);
    }

    Session? session;
    if (licensed) {
      try {
        session = await SessionStore.instance.read();
      } catch (error, stack) {
        debugPrint('[TVEXP STARTUP] Session restore failed: $error');
        debugPrintStack(stackTrace: stack);
      }
    }

    if (!mounted) return;
    setState(() {
      _licensed = licensed;
      _signedIn = licensed && session != null;
      _licenseMessage = licensed
          ? null
          : 'يلزم اتصال بالإنترنت للتحقق من الاشتراك أو إدخال كود صالح.';
      _ready = true;
    });

    // Update checks must not depend on license-server availability.
    // A temporary licensing API outage must never block app updates.
    if (restoreError != null) {
      debugPrint('[TVEXP STARTUP] Continuing startup after license error.');
    }
    _checkForUpdate();
  }

  Future<void> _onLicenseActivated() async {
    final session = await SessionStore.instance.read();
    if (!mounted) return;
    setState(() {
      _licensed = true;
      _signedIn = session != null;
      _licenseMessage = null;
    });
  }

  Future<void> _checkForUpdate() async {
    if (_updateCheckStarted) return;
    _updateCheckStarted = true;
    // Allow startup, network and license restoration to settle before checking.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final update = await UpdateService.check();
    if (!mounted) return;

    if (update == null) {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('فحص تحديث TVEXP'),
          content: SelectableText(UpdateService.lastCheckMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إغلاق'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _updateCheckStarted = false;
                _checkForUpdate();
              },
              child: const Text('إعادة الفحص'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _UpdateDialog(update: update),
    );
  }

  void _onSignedIn() => setState(() => _signedIn = true);
  void _onSignOut() async {
    await SessionStore.instance.clear();
    if (mounted) setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7956E8);
    final dark = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF0C111B),
      cardColor: const Color(0xFF172131),
      useMaterial3: true,
    );
    final light = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: seed),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'TVEXP IPTV',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: light,
      darkTheme: dark,
      themeMode: _themeMode,
      home: !_ready
          ? const _StartupScreen()
          : !_licensed
              ? LicenseScreen(
                  onActivated: _onLicenseActivated,
                  initialMessage: _licenseMessage,
                )
              : _signedIn
                  ? HomeShell(
                      onSignOut: _onSignOut,
                      onThemeChanged: (v) => setState(() => _themeMode = v),
                    )
                  : LoginScreen(onSignedIn: _onSignedIn),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});
  final TvexpUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double? _progress;
  String? _error;

  Future<void> _update() async {
    setState(() {
      _downloading = true;
      _error = null;
      _progress = 0;
    });
    try {
      await UpdateService.downloadAndInstall(
        widget.update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() => _progress = total > 0 ? received / total : null);
        },
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر تنزيل التحديث أو بدء التثبيت. تحقق من الاتصال وحاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تحديث جديد متاح'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('يتوفر إصدار TVEXP ${widget.update.version}.'),
            const SizedBox(height: 12),
            if (_downloading) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              const Text('جارٍ تنزيل التحديث...'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _downloading ? null : () => Navigator.pop(context),
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            onPressed: _downloading ? null : _update,
            child: Text(_downloading ? 'جارٍ التحديث...' : 'تحديث الآن'),
          ),
        ],
      );
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
