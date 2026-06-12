import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/supabase/chat_service.dart';
import '../../../../core/supabase_client.dart';
import 'chat_detail_screen.dart';

class KlantChatLijstScreen extends StatefulWidget {
  const KlantChatLijstScreen({
    super.key,
    this.embeddedInShell = false,
  });

  /// Geen eigen AppBar wanneer ingebed in [KlantScaffold] (voorkomt dubbele balk).
  final bool embeddedInShell;

  @override
  State<KlantChatLijstScreen> createState() => _KlantChatLijstScreenState();
}

class _KlantChatLijstScreenState extends State<KlantChatLijstScreen> {
  final ChatService _chatService = ChatService();

  late Future<List<Map<String, dynamic>>> _chatsFuture;
  Map<String, dynamic>? _selectedTicket;

  @override
  void initState() {
    super.initState();
    _chatsFuture = _chatService.fetchMijnChats();
  }

  void _herlaadChats() {
    setState(() {
      _chatsFuture = _chatService.fetchMijnChats();
    });
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String? get _currentUserId => AppSupabase.client.auth.currentUser?.id;

  String _projectTitel(Map<String, dynamic> ticket) {
    final projectNaam = _text(ticket['project_naam']);
    if (projectNaam.isNotEmpty) return projectNaam;

    var onderwerp = _text(ticket['onderwerp']);
    final lower = onderwerp.toLowerCase();
    if (lower.startsWith('project:')) {
      onderwerp = onderwerp.substring(onderwerp.indexOf(':') + 1).trim();
    }
    return onderwerp.isEmpty ? 'Project' : onderwerp;
  }

  String _laatsteBerichtPreview(Map<String, dynamic> ticket) {
    final raw = ticket['ticket_berichten'];
    final berichten = raw is List ? raw : const <dynamic>[];
    if (berichten.isEmpty) {
      return 'Start een gesprek met kantoor...';
    }

    final gesorteerd = berichten
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(_text(a['verzonden_op']));
        final db = DateTime.tryParse(_text(b['verzonden_op']));
        if (da == null && db == null) return 0;
        if (da == null) return -1;
        if (db == null) return 1;
        return da.compareTo(db);
      });

    final laatste = gesorteerd.last;
    final tekst = _text(laatste['bericht_inhoud']);
    if (tekst.isEmpty) {
      return 'Nieuw projectkanaal geopend';
    }
    return tekst;
  }

  bool _isTicketSelected(Map<String, dynamic> ticket) {
    if (_selectedTicket == null) return false;
    return _text(_selectedTicket!['id']) == _text(ticket['id']);
  }

  void _markeerTicketLokaalGelezen(Map<String, dynamic> ticket) {
    final myId = _currentUserId;
    if (myId == null) return;
    final berichten = ticket['ticket_berichten'];
    if (berichten is! List) return;
    for (final b in berichten) {
      if (b is Map && _text(b['afzender_id']) != myId) {
        b['is_gelezen'] = true;
      }
    }
  }

  Future<void> _onChatTap(
    Map<String, dynamic> ticket, {
    required bool isDesktop,
  }) async {
    final id = _text(ticket['id']);
    if (id.isEmpty) return;

    _chatService.markeerAlsGelezen(id);

    if (isDesktop) {
      setState(() {
        _markeerTicketLokaalGelezen(ticket);
        _selectedTicket = ticket;
      });
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatDetailScreen(
          ticketId: id,
          ticketData: ticket,
        ),
      ),
    );
    if (!mounted) return;
    _herlaadChats();
  }

  String _avatarLetter(String titel) {
    final t = titel.trim();
    if (t.isEmpty) return '?';
    return t[0].toUpperCase();
  }

  Widget _chatRow(Map<String, dynamic> ticket, {required bool isDesktop}) {
    final titel = _projectTitel(ticket);
    final preview = _laatsteBerichtPreview(ticket);
    final isSelected = isDesktop && _isTicketSelected(ticket);
    final myId = _currentUserId ?? '';

    final berichten = ticket['ticket_berichten'] as List<dynamic>? ?? [];
    final unreadCount = berichten.where((b) {
      if (b is! Map) return false;
      return b['is_gelezen'] == false && b['afzender_id'] != myId;
    }).length;
    final hasUnread = unreadCount > 0;

    var datumTekst = '';
    if (berichten.isNotEmpty) {
      final last = berichten.last;
      if (last is Map && last['verzonden_op'] != null) {
        final date =
            DateTime.parse(last['verzonden_op'].toString()).toLocal();
        final now = DateTime.now();
        final isVandaag = date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
        datumTekst = isVandaag
            ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
            : '${date.day}-${date.month}';
      }
    }

    final rowColor = isSelected || hasUnread
        ? Colors.blue.shade50
        : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _onChatTap(ticket, isDesktop: isDesktop),
          child: Container(
            color: rowColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    _avatarLetter(titel),
                    style: GoogleFonts.inter(
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titel,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        style: GoogleFonts.inter(
                          color: hasUnread
                              ? Colors.black87
                              : Colors.grey.shade600,
                          fontSize: 14,
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (datumTekst.isNotEmpty)
                      Text(
                        datumTekst,
                        style: GoogleFonts.inter(
                          color: hasUnread
                              ? Colors.blue.shade700
                              : Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight:
                              hasUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (hasUnread)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          unreadCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 20),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 74),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
        ),
      ],
    );
  }

  Widget _buildChatLijst({required bool isDesktop}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isDesktop)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              'Jouw projectkanalen — chat direct met je facilitator.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        if (isDesktop)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Text(
              'Chats',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.blue.shade900,
              ),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _chatsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final chats = snapshot.data ?? const [];
              if (chats.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Er zijn nog geen projectkanalen voor jouw account.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _herlaadChats(),
                child: ListView.builder(
                  itemCount: chats.length,
                  itemBuilder: (context, index) =>
                      _chatRow(chats[index], isDesktop: isDesktop),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMasterDetailBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return Row(
            children: [
              SizedBox(
                width: 350,
                child: _buildChatLijst(isDesktop: true),
              ),
              VerticalDivider(width: 1, color: Colors.grey.shade300),
              Expanded(
                child: _selectedTicket == null
                    ? ColoredBox(
                        color: Colors.grey.shade50,
                        child: Center(
                          child: Text(
                            'Selecteer een chat om het gesprek te starten',
                            style: GoogleFonts.inter(
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    : ChatDetailScreen(
                        key: ValueKey(_text(_selectedTicket!['id'])),
                        ticketId: _text(_selectedTicket!['id']),
                        ticketData: _selectedTicket!,
                        isSplitScreen: true,
                      ),
              ),
            ],
          );
        }

        return _buildChatLijst(isDesktop: false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.embeddedInShell
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              iconTheme: IconThemeData(color: Colors.blue.shade900),
              title: Text(
                'Mijn Berichten',
                style: GoogleFonts.inter(
                  color: Colors.blue.shade900,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
      body: _buildMasterDetailBody(),
    );
  }
}
