import 'package:supabase_flutter/supabase_flutter.dart';

class EmailService {
  /// Sends an email via Supabase Edge Function `send_email`.
  ///
  /// Returns `true` on success, `false` on failure.
  static Future<bool> sendEmail({
    required String to,
    required String subject,
    required String htmlBody,
    String? fromEmail,
    String? fromName,
    List<Map<String, dynamic>>? attachments,
  }) async {
    try {
      final body = <String, dynamic>{
        'to': to,
        'subject': subject,
        'html': htmlBody,
      };

      if (attachments != null) body['attachments'] = attachments;
      if (fromEmail != null) body['fromEmail'] = fromEmail;
      if (fromName != null) body['fromName'] = fromName;

      final res = await Supabase.instance.client.functions.invoke(
            'send_email',
            body: body,
          );

      if (res.status != 200) {
        // ignore: avoid_print
        print('send_email failed: status=${res.status}, data=${res.data}');
        return false;
      }

      final data = res.data;
      if (data is Map && data['success'] == true) return true;
      return true;
    } catch (e, st) {
      // ignore: avoid_print
      print('send_email error: $e\n$st');
      return false;
    }
  }
}

