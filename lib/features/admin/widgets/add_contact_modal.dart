import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddContactModal extends StatefulWidget {
  final String bedrijfId;
  const AddContactModal({super.key, required this.bedrijfId});

  @override
  State<AddContactModal> createState() => _AddContactModalState();
}

class _AddContactModalState extends State<AddContactModal> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _functionController = TextEditingController();
  bool _isBillingContact = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _functionController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    // Basic validation
    if (_firstNameController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('contactpersonen').insert({
        'bedrijf_id': widget.bedrijfId,
        'voornaam': _firstNameController.text.trim(),
        'achternaam': _lastNameController.text.trim(),
        'email': _emailController.text.trim(),
        'telefoon': _phoneController.text.trim(),
        'functie': _functionController.text.trim(),
        'is_facturatie_contact': _isBillingContact,
      });

      if (mounted) {
        // Return 'true' to signal success to the parent screen safely
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fout: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nieuw Contact',
                    style: GoogleFonts.lato(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildField('Voornaam', _firstNameController),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField('Achternaam', _lastNameController),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildField(
                'E-mailadres',
                _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              _buildField(
                'Telefoon',
                _phoneController,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildField('Functie', _functionController),
              const SizedBox(height: 16),
              CupertinoFormRow(
                prefix: const Text('Is facturatie contact?'),
                child: CupertinoSwitch(
                  value: _isBillingContact,
                  activeTrackColor: Colors.blueAccent,
                  onChanged: _isSaving
                      ? null
                      : (val) => setState(() => _isBillingContact = val),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveContact,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _isSaving
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Contact Opslaan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

