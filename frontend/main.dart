import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const PlaceMateApp());

/// ---------- THE APP ----------
class PlaceMateApp extends StatelessWidget {
  const PlaceMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Brand colors
    const primary = Color(0xFF4F46E5); // indigo
    const surface = Color(0xFFF7F7FB);
    final textTheme = GoogleFonts.interTextTheme(
      Theme.of(context).textTheme,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PlaceMate Recommender',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: primary),
        useMaterial3: true,
        scaffoldBackgroundColor: surface,
        textTheme: textTheme,
        chipTheme: ChipThemeData(
          labelStyle: textTheme.bodyMedium!,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          side: const BorderSide(color: Color(0xFFE6E6F0)),
          backgroundColor: Colors.white,
        ),
      ),
      home: const ChatPage(),
    );
  }
}

/// ---------- MODELS ----------
enum Sender { user, bot }

class ChatMessage {
  final Sender sender;
  final String text;
  final List<PlaceCard> places; // optional, used when bot returns results

  ChatMessage({
    required this.sender,
    required this.text,
    this.places = const [],
  });
}

class PlaceCard {
  final String name;
  final String address;
  final double score;

  PlaceCard({
    required this.name,
    required this.address,
    required this.score,
  });
}

/// ---------- CHAT PAGE ----------
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const baseUrl = 'http://10.0.2.2:8000';

  final controller = TextEditingController();
  final inputFocus = FocusNode();
  final scroll = ScrollController();

  final List<ChatMessage> messages = [
    ChatMessage(
      sender: Sender.bot,
      text:
      "Hi! I’m PlaceMate. Tell me what you’re looking for and I’ll recommend places.\n\n"
          "Try: **quiet coworking with fast Wi-Fi in Colombo**",
    ),
  ];

  bool typing = false;

  final List<String> quickPrompts = const [
    'quiet coworking with fast wifi',
    'meeting rooms + parking',
    'good coffee & comfy seating',
    'near Bambalapitiya',
  ];

  Future<void> _send(String query) async {
    final text = query.trim();
    if (text.isEmpty || typing) return;

    setState(() {
      messages.add(ChatMessage(sender: Sender.user, text: text));
      typing = true;
    });

    // Clear the input right away so it doesn't linger
    controller.clear();
    // Keep focus for faster multi-message flow (comment next line to unfocus)
    inputFocus.requestFocus();

    _scrollToEnd();

    try {
      final res = await http
          .post(
        Uri.parse('$baseUrl/recommend'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text, 'top_k': 5}),
      )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (body['results'] as List)
            .map((e) => PlaceCard(
          name: e['name'] as String? ?? 'Unknown',
          address: e['address'] as String? ?? '',
          score: (e['score'] as num?)?.toDouble() ?? 0.0,
        ))
            .toList();

        setState(() {
          messages.add(ChatMessage(
            sender: Sender.bot,
            text: "Here are a few places you might like:",
            places: results,
          ));
        });
      } else {
        setState(() {
          messages.add(ChatMessage(
            sender: Sender.bot,
            text:
            "I couldn’t fetch recommendations (code ${res.statusCode}). Please try again.",
          ));
        });
      }
    } catch (e) {
      setState(() {
        messages.add(ChatMessage(
          sender: Sender.bot,
          text:
          "Network issue 🤕\nCheck your connection/API and try again.\n\nError: $e",
        ));
      });
    } finally {
      setState(() => typing = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scroll.hasClients) return;
      scroll.animateTo(
        scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    controller.dispose();
    inputFocus.dispose();
    scroll.dispose();
    super.dispose();
  }

  /// ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Text('PlaceMate',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                )),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear chat',
            onPressed: () => setState(() {
              messages
                ..clear()
                ..add(ChatMessage(
                  sender: Sender.bot,
                  text:
                  "Cleared ✅\nTell me what you need and I’ll recommend places.",
                ));
              controller.clear();
              typing = false;
              _scrollToEnd();
            }),
            icon: const Icon(Icons.delete_outline),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Suggestions
            SizedBox(
              height: 48,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) => ActionChip(
                  label: Text(quickPrompts[i]),
                  onPressed: () {
                    controller.text = quickPrompts[i];
                    _send(quickPrompts[i]);
                  },
                ),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemCount: quickPrompts.length,
              ),
            ),
            const SizedBox(height: 8),

            // Chat list
            Expanded(
              child: Scrollbar(
                controller: scroll,
                child: ListView.builder(
                  controller: scroll,
                  physics: const BouncingScrollPhysics(),
                  keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    12 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  itemCount: messages.length + (typing ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (typing && index == messages.length) {
                      return const _TypingBubble();
                    }
                    final m = messages[index];
                    return Align(
                      alignment: m.sender == Sender.user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _MessageBubble(message: m),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Composer
            _Composer(
              controller: controller,
              focusNode: inputFocus,
              onSend: _send,
              enabled: !typing,
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------- WIDGETS ----------
class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String text) onSend;
  final bool enabled;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      color: theme.scaffoldBackgroundColor,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: onSend,
              decoration: InputDecoration(
                hintText: "Ask for places…",
                hintStyle:
                TextStyle(color: Colors.black.withOpacity(.45)),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            heroTag: 'send',
            onPressed: enabled ? () => onSend(controller.text) : null,
            child: const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == Sender.user;
    final theme = Theme.of(context);

    final bg = isUser
        ? LinearGradient(colors: [
      theme.colorScheme.primary,
      theme.colorScheme.primary.withOpacity(.85),
    ])
        : null;

    final bubble = Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isUser ? null : Colors.white,
        gradient: bg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 6),
          bottomRight: Radius.circular(isUser ? 6 : 16),
        ),
        boxShadow: isUser
            ? null
            : [BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 1)],
      ),
      child: Column(
        crossAxisAlignment:
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          SelectableText(
            message.text,
            style: TextStyle(
              color: isUser ? Colors.white : Colors.black87,
              fontSize: 15,
              height: 1.28,
            ),
          ),
          if (message.places.isNotEmpty) const SizedBox(height: 10),
          if (message.places.isNotEmpty)
            Column(
              children: message.places
                  .map((p) => _PlaceCardTile(card: p, tinted: !isUser))
                  .toList(),
            ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser)
          const CircleAvatar(
            radius: 14,
            backgroundColor: Color(0xFF4F46E5),
            child: Icon(Icons.bolt, size: 16, color: Colors.white),
          ),
        if (!isUser) const SizedBox(width: 8),
        Flexible(child: bubble),
        if (isUser) const SizedBox(width: 8),
        if (isUser)
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.person, size: 16, color: Colors.black87),
          ),
      ],
    );
  }
}

class _PlaceCardTile extends StatelessWidget {
  final PlaceCard card;
  final bool tinted; // true if inside white bubble -> use light divider

  const _PlaceCardTile({required this.card, required this.tinted});

  @override
  Widget build(BuildContext context) {
    final divider = tinted ? Colors.black12 : Colors.white24;
    final subtitle = TextStyle(
      color: Colors.black.withOpacity(.7),
      height: 1.25,
      fontSize: 13,
    );

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.place_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text(card.address, style: subtitle),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            card.score.toStringAsFixed(3),
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: Colors.black.withOpacity(.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(6),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Dot(), SizedBox(width: 4),
            _Dot(), SizedBox(width: 4),
            _Dot(),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot();
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: .3, end: 1.0).animate(
        CurvedAnimation(
          parent: c,
          curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
        ),
      ),
      child: const CircleAvatar(radius: 4, backgroundColor: Colors.black54),
    );
  }
}
