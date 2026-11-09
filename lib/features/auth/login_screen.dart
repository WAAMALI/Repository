import 'package:flutter/material.dart';
import '../../core/models/iptv_models.dart';
import '../../core/services/session_store.dart';
import '../../core/services/xtream_client.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});
  final VoidCallback onSignedIn;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _server.dispose(); _username.dispose(); _password.dispose(); super.dispose();
  }

  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    final credentials = XtreamCredentials(server: _server.text, username: _username.text.trim(), password: _password.text);
    try {
      final client = XtreamClient(credentials);
      await client.authenticate();
      client.close();
      await SessionStore.instance.save(credentials);
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 700;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 520 : 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _form,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Icon(Icons.live_tv_rounded, size: 58, color: Color(0xFF9878FF)),
                    const SizedBox(height: 12),
                    Text('TVEXP IPTV', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('اتصل باشتراك Xtream Codes', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 28),
                    TextFormField(controller: _server, keyboardType: TextInputType.url, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://server.example:8080', prefixIcon: Icon(Icons.dns_outlined)), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل عنوان السيرفر' : null),
                    const SizedBox(height: 14),
                    TextFormField(controller: _username, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)), validator: (v) => v == null || v.trim().isEmpty ? 'أدخل اسم المستخدم' : null),
                    const SizedBox(height: 14),
                    TextFormField(controller: _password, obscureText: _obscure, textDirection: TextDirection.ltr, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off))), validator: (v) => v == null || v.isEmpty ? 'أدخل كلمة المرور' : null),
                    if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: Colors.redAccent))],
                    const SizedBox(height: 22),
                    FilledButton.icon(onPressed: _busy ? null : _connect, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login), label: Text(_busy ? 'جارٍ الاتصال...' : 'اتصال')),
                    const SizedBox(height: 10),
                    Text('يدعم الإصدار الحالي تسجيل الدخول عبر Xtream Codes. دعم استيراد M3U سيضاف في مرحلة مصادر المحتوى.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
