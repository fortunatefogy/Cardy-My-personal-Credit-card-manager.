import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cards/credit_card.dart';
import 'gemini_chat_service.dart';

const _chatOrange = Color(0xFFFF7A00);
const _chatSurface = Color(0xFF1C1C1E);
const _chatMuted = Color(0xFFA1A1AA);

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key, required this.cards});
  final List<CreditCard> cards;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <({String role, String text})>[
    (role: 'assistant', text: 'Hi! Ask me which of your cards may be best for a purchase, or ask about the benefits you have saved.'),
  ];
  bool _loadingKey = true;
  bool _sending = false;
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _restoreKey();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreKey() async {
    try {
      final key = await GeminiChatService.instance.getApiKey();
      if (mounted) setState(() { _hasKey = key?.isNotEmpty == true; _loadingKey = false; });
    } catch (_) {
      if (mounted) setState(() { _hasKey = false; _loadingKey = false; });
    }
  }

  Future<void> _configureKey() async {
    final controller = TextEditingController();
    Future<dynamic>? dialogTransitionCompleted;
    final key = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        dialogTransitionCompleted = ModalRoute.of(dialogContext)?.completed;
        return AlertDialog(
        title: const Text('Connect Gemini Free Tier'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Add your Google AI Studio API key. It is encrypted on this phone. Chat messages and saved card benefit settings are sent to Google; avoid sharing secrets. Card number, expiry, CVV, and private notes are excluded.'),
          const SizedBox(height: 14),
          TextField(controller: controller, obscureText: true, decoration: const InputDecoration(labelText: 'Gemini API key')),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => launchUrl(Uri.parse('https://aistudio.google.com/app/apikey'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Get a free API key'),
          )),
        ]),
        actions: [
          if (_hasKey) TextButton(onPressed: () => Navigator.pop(dialogContext, ''), child: const Text('Remove key')),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
        ],
        );
      },
    );
    final exitedDialog = dialogTransitionCompleted;
    if (exitedDialog != null) await exitedDialog;
    controller.dispose();
    if (key == null) return;
    if (key.isEmpty) {
      await GeminiChatService.instance.clearApiKey();
      if (mounted) setState(() => _hasKey = false);
      return;
    }
    if (key.length < 20) {
      _notice('That key looks too short. Check the API key from Google AI Studio.');
      return;
    }
    try {
      await GeminiChatService.instance.saveApiKey(key);
      if (mounted) setState(() => _hasKey = true);
    } catch (error) {
      _notice('Could not securely save the API key: $error');
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_hasKey) {
      await _configureKey();
      if (!_hasKey) return;
    }
    _input.clear();
    setState(() {
      _messages.add((role: 'user', text: text));
      _sending = true;
    });
    _jumpToBottom();
    try {
      final key = await GeminiChatService.instance.getApiKey();
      if (key == null || key.isEmpty) throw const GeminiChatException('Add your Gemini API key in chat settings.');
      final answer = await GeminiChatService.instance.reply(
        apiKey: key,
        cards: widget.cards,
        history: List.unmodifiable(_messages),
      );
      if (mounted) setState(() => _messages.add((role: 'assistant', text: answer)));
    } catch (error) {
      if (mounted) setState(() => _messages.add((role: 'assistant', text: 'I couldn’t get a reply. $error')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _jumpToBottom();
    }
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: _chatOrange),
            const SizedBox(width: 9),
            const Expanded(child: Text('Gemini 3.5 Flash-Lite · Free tier', style: TextStyle(color: _chatMuted, fontSize: 13))),
            IconButton(tooltip: 'API key settings', onPressed: _configureKey, icon: const Icon(Icons.key)),
            IconButton(tooltip: 'New chat', onPressed: _sending ? null : () => setState(() => _messages
              ..clear()
              ..add((role: 'assistant', text: 'New chat started. What would you like to know about your cards?'))), icon: const Icon(Icons.add_comment_outlined)),
          ]),
        ),
        if (!_loadingKey && !_hasKey)
          Material(
            color: _chatSurface,
            child: InkWell(onTap: _configureKey, child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Icon(Icons.lock_outline, color: _chatOrange),
                const SizedBox(width: 10),
                const Expanded(child: Text('Connect a free Gemini API key to start chatting.', style: TextStyle(fontSize: 13))),
                TextButton(onPressed: _configureKey, child: const Text('Set up')),
              ]),
            )),
          ),
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          itemCount: _messages.length + (_sending ? 1 : 0),
          itemBuilder: (context, index) {
            if (_sending && index == _messages.length) {
              return const Align(alignment: Alignment.centerLeft, child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _chatOrange))));
            }
            final message = _messages[index];
            final isUser = message.role == 'user';
            return Align(
              alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isUser ? _chatOrange.withValues(alpha: .2) : _chatSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: isUser ? _chatOrange.withValues(alpha: .3) : Colors.white10),
                ),
                child: SelectableText(message.text, style: const TextStyle(height: 1.4)),
              ),
            );
          },
        )),
        Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.viewInsetsOf(context).bottom + 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _hasKey ? 'Ask about your cards…' : 'Set up Gemini to chat',
                filled: true,
                fillColor: _chatSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              ),
            )),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending || _loadingKey ? null : _send,
              style: IconButton.styleFrom(backgroundColor: _chatOrange, foregroundColor: Colors.black),
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Messages and saved card benefit settings go to Google Gemini. The free tier may use submitted content to improve Google products. Card numbers, expiry dates, CVVs, and private notes are excluded.', textAlign: TextAlign.center, style: TextStyle(color: _chatMuted, fontSize: 10)),
        ),
      ]);
}
