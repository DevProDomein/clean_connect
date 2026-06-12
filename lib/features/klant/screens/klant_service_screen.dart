import 'package:flutter/material.dart';

import 'chat/klant_chat_lijst_screen.dart';

/// Service-tab in [KlantScaffold] — meldingen & chat inbox.
class KlantServiceScreen extends StatelessWidget {
  const KlantServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const KlantChatLijstScreen(embeddedInShell: true);
  }
}
