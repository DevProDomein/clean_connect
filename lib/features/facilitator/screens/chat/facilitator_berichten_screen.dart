import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/supabase/chat_service.dart';
import '../../../../core/supabase_client.dart';
import '../../../klant/screens/chat/chat_detail_screen.dart';

/// Facilitator-dashboard: klant-chats + operator-meldingen in tabs.
class FacilitatorBerichtenScreen extends StatelessWidget {
  const FacilitatorBerichtenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: Colors.blue.shade900),
          title: Text(
            'Berichten & Meldingen',
            style: GoogleFonts.inter(
              color: Colors.blue.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: TabBar(
            labelColor: Colors.blue.shade900,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade900,
            labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.w500),
            tabs: const [
              Tab(text: 'Klant Chats'),
              Tab(text: 'Operator Meldingen'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _FacilitatorKlantChatsTab(),
            _FacilitatorOperatorMeldingenTab(),
          ],
        ),
      ),
    );
  }
}

class _FacilitatorKlantChatsTab extends StatefulWidget {
  const _FacilitatorKlantChatsTab();

  @override
  State<_FacilitatorKlantChatsTab> createState() =>
      _FacilitatorKlantChatsTabState();
}

class _FacilitatorKlantChatsTabState extends State<_FacilitatorKlantChatsTab> {
  final ChatService _chatService = ChatService();

  String _searchQuery = '';
  List<Map<String, dynamic>> _alleChats = [];
  bool _loadingChats = true;
  Map<String, dynamic>? _selectedTicket;

  List<Map<String, dynamic>> get _gefilterdeChats {
    if (_searchQuery.isEmpty) return _alleChats;
    final q = _searchQuery.toLowerCase();
    return _alleChats.where((chat) {
      final onderwerp = _text(chat['onderwerp']).toLowerCase();
      final bedrijf = _bedrijfsnaam(chat).toLowerCase();
      final project = _projectNaam(chat).toLowerCase();
      return onderwerp.contains(q) ||
          bedrijf.contains(q) ||
          project.contains(q);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  Future<void> _loadChats() async {
    final data = await _chatService.fetchFacilitatorChats();
    if (!mounted) return;
    setState(() {
      _alleChats = data;
      _loadingChats = false;
    });
  }

  void _herlaadChats() {
    setState(() => _loadingChats = true);
    _loadChats();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String? get _currentUserId => AppSupabase.client.auth.currentUser?.id;

  String _bedrijfsnaam(Map<String, dynamic> ticket) {
    final raw = ticket['bedrijven'];
    if (raw is Map) return _text(raw['bedrijfsnaam']);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return _text((raw.first as Map)['bedrijfsnaam']);
    }
    return 'Onbekend bedrijf';
  }

  String _projectNaam(Map<String, dynamic> ticket) {
    final direct = _text(ticket['project_naam']);
    if (direct.isNotEmpty) return direct;
    final raw = ticket['projecten'];
    if (raw is Map) return _text(raw['project_naam']);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return _text((raw.first as Map)['project_naam']);
    }
    return '';
  }

  String _laatsteBerichtPreview(Map<String, dynamic> ticket) {
    final raw = ticket['ticket_berichten'];
    final berichten = raw is List ? raw : const <dynamic>[];
    if (berichten.isEmpty) return 'Nog geen berichten';

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

    final tekst = _text(gesorteerd.last['bericht_inhoud']);
    return tekst.isEmpty ? 'Nieuw kanaal geopend' : tekst;
  }

  String _subtitel(Map<String, dynamic> ticket) {
    final onderwerp = _text(ticket['onderwerp']);
    final preview = _laatsteBerichtPreview(ticket);
    if (onderwerp.isEmpty) return preview;
    return '$onderwerp · $preview';
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
    final titel = _bedrijfsnaam(ticket);
    final subtitel = _subtitel(ticket);
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
                        subtitel,
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Zoek op bedrijf of onderwerp...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.blue.shade900, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildChatLijst({required bool isDesktop}) {
    if (_loadingChats && _alleChats.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearchBar(),
        Expanded(
          child: _alleChats.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Er zijn nog geen actieve klant-chats.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ),
                )
              : _gefilterdeChats.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Geen chats gevonden voor "$_searchQuery".',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadChats,
                      child: ListView.builder(
                        itemCount: _gefilterdeChats.length,
                        itemBuilder: (context, index) => _chatRow(
                          _gefilterdeChats[index],
                          isDesktop: isDesktop,
                        ),
                      ),
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        if (isDesktop) {
          return Row(
            children: [
              SizedBox(
                width: 380,
                child: _buildChatLijst(isDesktop: true),
              ),
              VerticalDivider(width: 1, color: Colors.grey.shade300),
              Expanded(
                child: _selectedTicket == null
                    ? ColoredBox(
                        color: Colors.grey.shade50,
                        child: Center(
                          child: Text(
                            'Selecteer een chat om het gesprek te openen',
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
}

class _FacilitatorOperatorMeldingenTab extends StatefulWidget {
  const _FacilitatorOperatorMeldingenTab();

  @override
  State<_FacilitatorOperatorMeldingenTab> createState() =>
      _FacilitatorOperatorMeldingenTabState();
}

class _FacilitatorOperatorMeldingenTabState
    extends State<_FacilitatorOperatorMeldingenTab> {
  final ChatService _chatService = ChatService();
  final DateFormat _datumFmt = DateFormat('d MMM HH:mm', 'nl_NL');

  List<Map<String, dynamic>> _operatorMeldingen = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOperatorMeldingen();
  }

  Future<void> _loadOperatorMeldingen() async {
    setState(() => _isLoading = true);
    try {
      final operatorMessages = await _chatService.fetchOperatorMeldingen();
      if (!mounted) return;
      setState(() {
        _operatorMeldingen = operatorMessages;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Fout bij ophalen operator meldingen: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  Map<String, dynamic>? _nestedMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  String _operatorNaam(Map<String, dynamic> bericht) {
    final g = _nestedMap(bericht['gebruikers']);
    if (g == null) return 'Operator';
    final naam = '${_text(g['voornaam'])} ${_text(g['achternaam'])}'.trim();
    return naam.isEmpty ? 'Operator' : naam;
  }

  String _projectLabel(Map<String, dynamic> bericht) {
    final ticket = _nestedMap(bericht['tickets']);
    final onderwerp = _text(ticket?['onderwerp']);
    if (onderwerp.isNotEmpty) return onderwerp;
    return 'Project';
  }

  String _meldingTekst(Map<String, dynamic> bericht) {
    return ChatService.leesBerichtInhoud(bericht).trim();
  }

  String _datumLabel(Map<String, dynamic> bericht) {
    final dt = DateTime.tryParse(_text(bericht['verzonden_op']));
    if (dt == null) return '';
    return _datumFmt.format(dt.toLocal());
  }

  Map<String, dynamic> _ticketDataVoorChat(Map<String, dynamic> bericht) {
    final ticketId = _text(bericht['ticket_id']);
    final ticket = _nestedMap(bericht['tickets']);
    final data = <String, dynamic>{'id': ticketId};
    if (ticket != null) {
      data.addAll(ticket);
    }
    return data;
  }

  void _openProjectChat(Map<String, dynamic> bericht) {
    final ticketId = _text(bericht['ticket_id']);
    if (ticketId.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatDetailScreen(
          ticketId: ticketId,
          ticketData: _ticketDataVoorChat(bericht),
        ),
      ),
    );
  }

  Widget _meldingRow(Map<String, dynamic> bericht) {
    final operatorNaam = _operatorNaam(bericht);
    final project = _projectLabel(bericht);
    final tekst = _meldingTekst(bericht);
    final datum = _datumLabel(bericht);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _openProjectChat(bericht),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.orange.shade100,
                  child: Icon(
                    Icons.engineering_outlined,
                    color: Colors.orange.shade800,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              operatorNaam,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (datum.isNotEmpty)
                            Text(
                              datum,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        project,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tekst,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: Colors.grey.shade800,
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            'Open project-chat',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue.shade700,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: Colors.blue.shade700,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 66),
          child: Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _operatorMeldingen.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_operatorMeldingen.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nog geen operator-meldingen vanaf de werkvloer.',
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
      onRefresh: _loadOperatorMeldingen,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 4),
        itemCount: _operatorMeldingen.length,
        itemBuilder: (context, index) =>
            _meldingRow(_operatorMeldingen[index]),
      ),
    );
  }
}
