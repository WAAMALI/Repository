import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/app_database.dart';
import '../../core/services/license_service.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.title,
    required this.url,
    this.mediaId,
    this.section = 'media',
    this.image,
    this.isLive = false,
    this.isLocalFile = false,
  });

  final String title;
  final String url;
  final String? mediaId;
  final String section;
  final String? image;
  final bool isLive;
  final bool isLocalFile;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  static const MethodChannel _playerChannel =
      MethodChannel('com.tvexp.iptv/player');

  bool _launching = true;
  bool _opened = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openExternalPlayer());
  }

  Future<void> _openExternalPlayer() async {
    if (!mounted) return;
    if (widget.url.trim().isEmpty) {
      setState(() {
        _launching = false;
        _error = 'رابط التشغيل فارغ أو غير صالح.';
      });
      return;
    }

    setState(() {
      _launching = true;
      _error = null;
    });

    try {
      await LicenseService.instance.ensureValid();
      await _playerChannel.invokeMethod<bool>('openExternalPlayer', {
        'url': widget.url,
        'title': widget.title,
        'isLocalFile': widget.isLocalFile,
        'isLive': widget.isLive,
      });

      final id = widget.mediaId;
      if (!widget.isLive && id != null && id.trim().isNotEmpty) {
        await AppDatabase.instance.recordProgress(
          id: id,
          name: widget.title,
          section: widget.section,
          image: widget.image,
          positionMs: 0,
          durationMs: 0,
        );
      }

      if (!mounted) return;
      setState(() {
        _launching = false;
        _opened = true;
      });
    } on LicenseException catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.message;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.code == 'NO_EXTERNAL_PLAYER'
            ? 'لم يتم العثور على مشغل فيديو خارجي. ثبّت VLC أو أي مشغل يدعم روابط IPTV ثم حاول مرة أخرى.'
            : (e.message ?? 'تعذر فتح المشغل الخارجي.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = 'تعذر فتح الفيديو: $e';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _opened && mounted) {
      // The external player has returned control to TVEXP.
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _error == null
                    ? Icons.open_in_new_rounded
                    : Icons.play_disabled_rounded,
                color: Colors.white70,
                size: 56,
              ),
              const SizedBox(height: 18),
              Text(
                _launching
                    ? 'جارٍ فتح مشغل الفيديو الخارجي...'
                    : _error ?? 'تم إرسال الفيديو إلى المشغل الخارجي.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
              if (_launching) ...[
                const SizedBox(height: 20),
                const CircularProgressIndicator(),
              ],
              if (!_launching && _error != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openExternalPlayer,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
              if (!_launching && _opened) ...[
                const SizedBox(height: 12),
                const Text(
                  'يمكنك الرجوع إلى TVEXP في أي وقت.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _openExternalPlayer,
                  icon: const Icon(Icons.replay),
                  label: const Text('فتح المشغل مرة أخرى'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
