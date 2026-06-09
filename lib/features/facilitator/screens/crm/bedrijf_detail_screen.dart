import '../../../admin/screens/relation_detail_screen.dart';

/// Facilitator CRM — bedrijfsdetail met stamgegevens en contactpersonen.
class BedrijfDetailScreen extends RelationDetailScreen {
  const BedrijfDetailScreen({
    super.key,
    required super.bedrijfId,
    super.createAsKlant,
    super.initialTabIndex,
  });
}
