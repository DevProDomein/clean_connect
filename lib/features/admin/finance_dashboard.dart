import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/translations.dart';
import '../../core/widgets/app_drawer.dart';

class FinanceDashboard extends StatefulWidget {
  const FinanceDashboard({super.key});

  @override
  State<FinanceDashboard> createState() => _FinanceDashboardState();
}

class _FinanceDashboardState extends State<FinanceDashboard> {
  Future<List<Map<String, dynamic>>> _fetchBankTransacties() async {
    final res = await AppSupabase.client
        .from('bank_transacties')
        .select()
        .order('datum', ascending: false)
        .limit(20);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _fetchOcrScans() async {
    final res = await AppSupabase.client
        .from('ocr_scans')
        .select()
        .order('created_at', ascending: false)
        .limit(10);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> _fetchKwartaalCijfers() async {
    final res = await AppSupabase.client
        .from('dashboard_kwartaal_cijfers')
        .select()
        .order('kwartaal', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexts.get('admin_finance_title')),
        actions: [
          IconButton(
            tooltip: AppTexts.get('button_sign_out'),
            onPressed: () async => AppSupabase.client.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: AppTexts.get('finance_bank_matcher_title'),
              child: FutureBuilder(
                future: _fetchBankTransacties(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingBox();
                  }
                  if (snapshot.hasError) {
                    return _ErrorBox(error: snapshot.error);
                  }
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return _EmptyBox(
                      text: AppTexts.get('finance_no_transactions'),
                    );
                  }
                  return Column(
                    children: [
                      ...rows.take(10).map((t) {
                        final oms =
                            (t['omschrijving'] ?? t['description'] ?? '')
                                .toString();
                        final bedrag =
                            (t['bedrag'] ?? t['amount'] ?? '').toString();
                        final datum =
                            (t['datum'] ?? t['date'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          title:
                              Text(oms.isEmpty ? '(geen omschrijving)' : oms),
                          subtitle: Text(datum),
                          trailing: Text(bedrag),
                        );
                      }),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppTexts.get('finance_auto_match_todo'),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.auto_fix_high),
                          label: Text(AppTexts.get('finance_auto_match')),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: AppTexts.get('finance_scan_recognize_title'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppTexts.get('finance_take_upload_hint'),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.photo_camera),
                        label: Text(AppTexts.get('finance_take_photo')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                AppTexts.get('finance_take_upload_hint'),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.upload_file),
                        label: Text(AppTexts.get('finance_upload_photo')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder(
                    future: _fetchOcrScans(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const _LoadingBox();
                      }
                      if (snapshot.hasError) {
                        return _ErrorBox(error: snapshot.error);
                      }
                      final rows = snapshot.data ?? const [];
                      if (rows.isEmpty) {
                        return _EmptyBox(
                          text: AppTexts.get('finance_no_ocr_scans'),
                        );
                      }
                      return Column(
                        children: rows.take(5).map((s) {
                          final status =
                              (s['status'] ?? s['state'] ?? '').toString();
                          final createdAt = (s['created_at'] ?? '').toString();
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.document_scanner),
                            title: Text(
                              status.isEmpty ? '(onbekende status)' : status,
                            ),
                            subtitle: Text(createdAt),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _Section(
              title: AppTexts.get('finance_quarterly_reports_title'),
              child: FutureBuilder(
                future: _fetchKwartaalCijfers(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingBox();
                  }
                  if (snapshot.hasError) {
                    return _ErrorBox(error: snapshot.error);
                  }
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return _EmptyBox(text: AppTexts.get('finance_no_quarterly'));
                  }

                  return Column(
                    children: rows.map((r) {
                      final kwartaal =
                          (r['kwartaal'] ?? r['quarter'] ?? '').toString();
                      final revenueNum = _toNum(r['revenue'] ?? r['omzet']);
                      final costsNum = _toNum(r['costs'] ?? r['kosten']);
                      final net = (revenueNum ?? 0) - (costsNum ?? 0);

                      return Card(
                        child: ListTile(
                          title: Text(
                            kwartaal.isEmpty
                                ? AppTexts.get('finance_quarter_fallback')
                                : kwartaal,
                          ),
                          subtitle: Text(
                            '${AppTexts.get('finance_revenue')}: ${revenueNum ?? '-'} • '
                            '${AppTexts.get('finance_costs')}: ${costsNum ?? '-'}',
                          ),
                          trailing: Text('${AppTexts.get('finance_net')}: $net'),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text('Fout: $error'),
    );
  }
}

