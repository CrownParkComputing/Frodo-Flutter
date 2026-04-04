import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'archive_auth.dart';

class ArchiveSettingsPage extends StatefulWidget {
  const ArchiveSettingsPage({super.key});

  @override
  State<ArchiveSettingsPage> createState() => _ArchiveSettingsPageState();
}

class _ArchiveSettingsPageState extends State<ArchiveSettingsPage> {
  final ArchiveAuthService _authService = ArchiveAuthService.instance;

  late final WebViewController _controller;
  bool _checking = true;
  bool _hasSession = false;
  String? _cookiePreview;

  @override
  void initState() {
    super.initState();
    _controller =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (_) {
                _refreshStatus();
              },
            ),
          )
          ..loadRequest(Uri.parse('https://archive.org/account/login'));
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    setState(() => _checking = true);
    final cookies = await _authService.getArchiveCookies();
    final hasSession = await _authService.hasArchiveSession();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasSession = hasSession;
      _cookiePreview = cookies;
      _checking = false;
    });
  }

  Future<void> _clearSession() async {
    await _authService.clearArchiveCookies();
    await _controller.loadRequest(
      Uri.parse('https://archive.org/account/login'),
    );
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _cookiePreview;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Internet Archive Settings')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.white10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _hasSession ? Icons.verified_user : Icons.lock_outline,
                      color:
                          _hasSession
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _checking
                            ? 'Checking Archive session...'
                            : _hasSession
                            ? 'Archive session detected'
                            : 'Not signed in to Archive.org',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in below using your Internet Archive account. The app will reuse the Android WebView cookies for TOSEC downloads.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _refreshStatus,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Status'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearSession,
                      icon: const Icon(Icons.logout),
                      label: const Text('Clear Session'),
                    ),
                  ],
                ),
                if (preview != null && preview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Cookie preview: ${preview.length > 140 ? '${preview.substring(0, 140)}...' : preview}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Archive.org Login',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
