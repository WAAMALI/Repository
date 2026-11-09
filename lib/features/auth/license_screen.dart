import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/license_service.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({
    super.key,
    required this.onActivated,
    this.initialMessage,
  });

  final VoidCallback onActivated;
  final String? initialMessage;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialMessage;
    _loadSavedCode();
  }

  Future<void> _loadSavedCode() async {
    final saved = await LicenseService.instance.savedCode();
    if (!mounted || saved == null || _code.text.isNotEmpty) return;
    _code.text = saved;
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _code.text.trim();
    if (!RegExp(r'^\d{12}$').hasMatch(code)) {
      setState(() => _error = 'أدخل كود اشتراك صحيحًا مكونًا من 12 رقمًا.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await LicenseService.instance.activate(code);
      if (mounted) widget.onActivated();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 480 : 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 64,
                      color: Color(0xFFF5A20A),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'TVEXP IPTV',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل كود الاشتراك للمتابعة',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.center,
                      maxLength: 12,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'كود الاشتراك',
                        hintText: '000000000000',
                        prefixIcon: Icon(Icons.key),
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!_busy) _activate();
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _activate,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(
                        _busy ? 'جارٍ التحقق...' : 'تفعيل الاشتراك',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'يُربط الكود بأول جهاز يتم تفعيله عليه، ولا يمكن نقله إلى جهاز آخر.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
