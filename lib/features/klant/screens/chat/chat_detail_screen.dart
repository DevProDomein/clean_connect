import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/supabase/chat_service.dart';
import '../../../../core/supabase_client.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({
    super.key,
    required this.ticketId,
    required this.ticketData,
    this.isSplitScreen = false,
  });

  final String ticketId;
  final Map<String, dynamic> ticketData;
  final bool isSplitScreen;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  static const Color _chatBackground = Color(0xFFF7F7F5);

  final ChatService _chatService = ChatService();
  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final DateFormat _tijdFmt = DateFormat('HH:mm', 'nl_NL');

  bool _sending = false;
  bool _sendInFlight = false;
  bool _uploadingImage = false;
  XFile? _pendingImage;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_onInputChanged);
    unawaited(_chatService.markeerAlsGelezen(widget.ticketId));
  }

  void _markeerGelezenAsync() {
    unawaited(_chatService.markeerAlsGelezen(widget.ticketId));
  }

  @override
  void dispose() {
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _onInputChanged() => setState(() {});

  String _text(dynamic v) => (v ?? '').toString().trim();

  String? get _currentUserId => AppSupabase.client.auth.currentUser?.id;

  bool get _canSend =>
      !_sending &&
      !_uploadingImage &&
      (_inputController.text.trim().isNotEmpty || _pendingImage != null);

  String get _chatTitel {
    final project = widget.ticketData['projecten'];
    if (project is Map) {
      final naam = _text(project['project_naam']);
      if (naam.isNotEmpty) return naam;
    }
    if (project is List && project.isNotEmpty && project.first is Map) {
      final naam = _text((project.first as Map)['project_naam']);
      if (naam.isNotEmpty) return naam;
    }
    var onderwerp = _text(widget.ticketData['onderwerp']);
    if (onderwerp.toLowerCase().startsWith('project:')) {
      onderwerp = onderwerp.substring(onderwerp.indexOf(':') + 1).trim();
    }
    return onderwerp.isEmpty ? 'Project Chat' : onderwerp;
  }

  Future<void> _verstuur() async {
    if (_sendInFlight || _uploadingImage) return;

    final tekst = _inputController.text.trim();
    final pending = _pendingImage;
    if (tekst.isEmpty && pending == null) return;

    _sendInFlight = true;
    _inputController.clear();
    final clearedPending = pending;
    if (mounted) {
      setState(() {
        _sending = true;
        _pendingImage = null;
      });
    }

    try {
      String? mediaUrl;
      if (clearedPending != null) {
        if (mounted) setState(() => _uploadingImage = true);
        try {
          mediaUrl = await _chatService.uploadChatFoto(clearedPending);
        } finally {
          if (mounted) setState(() => _uploadingImage = false);
        }
      }

      await _chatService.verstuurBericht(
        widget.ticketId,
        tekst,
        mediaUrl: mediaUrl,
      );
    } catch (e) {
      if (!mounted) return;
      if (tekst.isNotEmpty) _inputController.text = tekst;
      if (clearedPending != null) {
        setState(() => _pendingImage = clearedPending);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Versturen mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _sendInFlight = false;
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickImage() async {
    if (_sending || _uploadingImage) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerij'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || source == null) return;

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 75,
      );
      if (!mounted || image == null) return;
      setState(() => _pendingImage = image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Foto kiezen mislukt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _afzenderNaam(Map<String, dynamic> bericht) {
    final raw = bericht['gebruikers'];
    Map<String, dynamic>? g;
    if (raw is Map) {
      g = Map<String, dynamic>.from(raw);
    } else if (raw is List && raw.isNotEmpty && raw.first is Map) {
      g = Map<String, dynamic>.from(raw.first as Map);
    }
    if (g != null) {
      final naam =
          '${_text(g['voornaam'])} ${_text(g['achternaam'])}'.trim();
      final rol = _text(g['rol']);
      if (naam.isNotEmpty && rol.isNotEmpty) return '$naam ($rol)';
      if (naam.isNotEmpty) return naam;
      if (rol.isNotEmpty) return rol;
    }
    return 'Gebruiker';
  }

  void _onBerichtLongPress(Map<String, dynamic> bericht) {
    final uid = _currentUserId;
    if (uid == null) return;

    final isMijnBericht = _text(bericht['afzender_id']) == uid;
    final isVerwijderd = ChatService.isBerichtVerwijderd(bericht);
    if (!isMijnBericht || isVerwijderd) return;

    final verzondenOp = DateTime.tryParse(_text(bericht['verzonden_op']));
    if (verzondenOp == null) return;

    if (DateTime.now().difference(verzondenOp.toLocal()).inMinutes < 60) {
      _showBerichtOptiesModal(context, bericht);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Berichten ouder dan 1 uur kunnen niet worden gewijzigd.',
          ),
        ),
      );
    }
  }

  void _showBerichtOptiesModal(
    BuildContext context,
    Map<String, dynamic> bericht,
  ) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Bericht bewerken'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBewerkDialog(bericht);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Bericht verwijderen'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await _chatService.deleteBericht(_text(bericht['id']));
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fout bij verwijderen: $e')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openBewerkDialog(Map<String, dynamic> bericht) {
    final editController = TextEditingController(
      text: ChatService.leesBerichtInhoud(bericht),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Bericht bewerken'),
          content: TextField(
            controller: editController,
            maxLines: 3,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuleren'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await _chatService.editBericht(
                    _text(bericht['id']),
                    editController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Fout bij bewerken: $e')),
                  );
                }
              },
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    ).whenComplete(editController.dispose);
  }

  Widget _messageBubble(Map<String, dynamic> bericht) {
    final uid = _currentUserId ?? '';
    final isMijnBericht = _text(bericht['afzender_id']) == uid;
    final isVerwijderd = ChatService.isBerichtVerwijderd(bericht);
    final isBewerkt = ChatService.isBerichtBewerkt(bericht);
    final afzenderNaam = _afzenderNaam(bericht);
    final inhoud = ChatService.leesBerichtInhoud(bericht).trim();
    final mediaUrl = _text(bericht['media_url']);
    final tijd = DateTime.tryParse(_text(bericht['verzonden_op']));
    final tijdLabel = tijd == null ? '' : _tijdFmt.format(tijd.toLocal());
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.50;

    return Align(
      alignment:
          isMijnBericht ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () => _onBerichtLongPress(bericht),
        onSecondaryTap: () => _onBerichtLongPress(bericht),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMijnBericht ? Colors.blue.shade700 : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMijnBericht ? 16 : 4),
              bottomRight: Radius.circular(isMijnBericht ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMijnBericht && !isVerwijderd) ...[
                Text(
                  afzenderNaam,
                  style: TextStyle(
                    color: Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              if (isVerwijderd)
                Text(
                  '🚫 Dit bericht is verwijderd',
                  style: TextStyle(
                    color: isMijnBericht ? Colors.white70 : Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                    fontSize: 14,
                  ),
                )
              else ...[
                if (mediaUrl.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: CachedNetworkImage(
                        imageUrl: mediaUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(
                          height: 160,
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (inhoud.isNotEmpty) const SizedBox(height: 8),
                ],
                if (inhoud.isNotEmpty)
                  Text(
                    inhoud,
                    style: TextStyle(
                      color: isMijnBericht ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBewerkt && !isVerwijderd)
                      Text(
                        '(bewerkt) ',
                        style: TextStyle(
                          color: isMijnBericht
                              ? Colors.white70
                              : Colors.grey.shade500,
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (tijdLabel.isNotEmpty)
                      Text(
                        tijdLabel,
                        style: TextStyle(
                          color: isMijnBericht
                              ? Colors.white70
                              : Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingImagePreview() {
    if (_pendingImage == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FutureBuilder<Uint8List>(
                  future: _pendingImage!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey.shade300,
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Image.memory(
                      snapshot.data!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    );
                  },
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _sending
                        ? null
                        : () => setState(() => _pendingImage = null),
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Text(
            'Foto klaar om te versturen',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          border: Border(top: BorderSide(color: Colors.grey.shade300)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pendingImagePreview(),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed:
                        (_sending || _uploadingImage) ? null : _pickImage,
                    icon: _uploadingImage
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.add_circle_outline,
                            color: Colors.blue.shade900,
                            size: 28,
                          ),
                  ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: (node, event) {
                        if (event is! KeyDownEvent) {
                          return KeyEventResult.ignored;
                        }
                        if (event.logicalKey != LogicalKeyboardKey.enter) {
                          return KeyEventResult.ignored;
                        }
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          return KeyEventResult.ignored;
                        }
                        if (_canSend) {
                          _verstuur();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        controller: _inputController,
                        focusNode: _inputFocusNode,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.send,
                        textCapitalization: TextCapitalization.sentences,
                        enableSuggestions: true,
                        onSubmitted: (_) {
                          if (_canSend) _verstuur();
                        },
                        decoration: InputDecoration(
                          hintText: 'Bericht',
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Material(
                    color: _canSend ? Colors.blue.shade600 : Colors.grey.shade400,
                    shape: const CircleBorder(),
                    elevation: _canSend ? 2 : 0,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _canSend ? _verstuur : null,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: _sending
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _chatBackground,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isSplitScreen,
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: widget.isSplitScreen ? 0 : 1,
        scrolledUnderElevation: widget.isSplitScreen ? 0 : 1,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _chatTitel,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chatService.streamBerichtenForTicket(widget.ticketId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Fout bij laden berichten: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final berichten = snapshot.data ?? const [];
                if (snapshot.hasData) {
                  _markeerGelezenAsync();
                }
                if (berichten.isEmpty) {
                  return Center(
                    child: Text(
                      'Nog geen berichten.\nStuur het eerste bericht!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: berichten.length,
                  itemBuilder: (context, index) =>
                      _messageBubble(berichten[index]),
                );
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }
}
