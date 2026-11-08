// Image → Prompt screen.
//
// Pick any image (or receive one from the Image Search screen), send it
// to the signed-in Gemini web session, and get back ONE detailed
// text-to-image prompt describing it — ready to paste into the Set
// Designer or copy anywhere. Uses GeminiApi.generatePromptFromImage,
// i.e. the same account, upload channel and session as generation.
//
// UI follows the app's existing style: FilledButton.icon for the main
// action, OutlinedButton.icon for secondary actions, the same dark
// surface boxes for status/output, 12-14px panel padding.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gemini_api.dart';
import 'login_screen.dart';

class ImageToPromptScreen extends StatefulWidget {
  /// Optional image handed in by the Image Search screen.
  final Uint8List? initialBytes;
  final String? initialName;
  final String? initialMime;

  const ImageToPromptScreen({
    super.key,
    this.initialBytes,
    this.initialName,
    this.initialMime,
  });

  @override
  State<ImageToPromptScreen> createState() => _ImageToPromptScreenState();
}

class _ImageToPromptScreenState extends State<ImageToPromptScreen> {
  Uint8List? _bytes;
  String _name = '';
  String _mime = 'image/jpeg';
  final TextEditingController _noteCtrl = TextEditingController();
  final TextEditingController _resultCtrl = TextEditingController();
  bool _busy = false;
  String _status = 'Pick an image, then tap "Generate prompt".';
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialBytes != null) {
      _bytes = widget.initialBytes;
      _name = widget.initialName ?? 'searched_image.jpg';
      _mime = widget.initialMime ?? 'image/jpeg';
      _status = 'Image loaded from Image Search. Tap "Generate prompt".';
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    _resultCtrl.dispose();
    super.dispose();
  }

  void _say(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _status = msg;
      _statusIsError = error;
    });
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    final lower = f.name.toLowerCase();
    final mime = lower.endsWith('.png')
        ? 'image/png'
        : lower.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    setState(() {
      _bytes = f.bytes;
      _name = f.name;
      _mime = mime;
    });
    _say('Image ready: ${f.name}. Tap "Generate prompt".');
  }

  bool get _looksLikeAuthError {
    final s = _status.toLowerCase();
    return s.contains('sign in') ||
        s.contains('session') ||
        s.contains('cookie') ||
        s.contains('401') ||
        s.contains('403');
  }

  Future<void> _generate() async {
    if (_busy || _bytes == null) return;
    setState(() => _busy = true);
    _say('Uploading image to your Gemini session and asking for a prompt...');
    try {
      final api = GeminiApi();
      final prompt = await api.generatePromptFromImage(
        _bytes!,
        _name.isEmpty ? 'image.jpg' : _name,
        mimeType: _mime,
        styleNote: _noteCtrl.text,
      );
      if (!mounted) return;
      setState(() => _resultCtrl.text = prompt);
      _say('Prompt ready. Copy it, or send it straight to the Set Designer.');
    } catch (e) {
      _say('Image-to-prompt failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LoginScreen(onConnected: () {
              _say('Gemini connected. Tap "Generate prompt" again.');
            })));
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _resultCtrl.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image to Prompt'),
        actions: [
          IconButton(
            tooltip: 'Gemini Login',
            onPressed: _openLogin,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Turn any image into a ready-to-use AI generation prompt with '
              'your signed-in Gemini account.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_bytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_bytes!,
                    height: 220, fit: BoxFit.contain),
              ),
              const SizedBox(height: 6),
              Text(_name,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickImage,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(_bytes == null ? 'Pick an image' : 'Change image'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Style note (optional)',
                hintText: 'e.g. AMOLED dark, neon, minimal',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _bytes == null ? null : _generate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Working...' : 'Generate prompt'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: TextStyle(
                  fontSize: 13,
                  color: _statusIsError
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ),
            if (_statusIsError && _looksLikeAuthError) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openLogin,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Open Gemini Login'),
              ),
            ],
            if (hasResult) ...[
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Generated prompt',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _resultCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _resultCtrl.text.trim()));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Prompt copied')));
                    },
                    icon: const Icon(Icons.copy, size: 15),
                    label: const Text('Copy prompt'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context)
                        .pop(_resultCtrl.text.trim()),
                    icon: const Icon(Icons.design_services_outlined, size: 15),
                    label: const Text('Use in Set Designer'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
