import 'package:web/web.dart' as web;

bool hardRedirectToOriginImpl() {
  // Using package:web avoids deprecated dart:html.
  web.window.location.href = web.window.location.origin;
  return true;
}

