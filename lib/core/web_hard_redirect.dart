import 'web_hard_redirect_stub.dart'
    if (dart.library.html) 'web_hard_redirect_web.dart';

/// Performs a hard redirect to the app's origin on Flutter Web.
///
/// Returns `true` when a hard redirect was triggered (web), otherwise `false`.
bool hardRedirectToOrigin() => hardRedirectToOriginImpl();

