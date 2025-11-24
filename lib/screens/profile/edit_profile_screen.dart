import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../../core/api_client.dart';
import '../../core/supabase_client.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bandCtrl;
  bool _saving = false;
  bool _avatarUploading = false;
  String? _avatarUrl;
  final _picker = ImagePicker();
  final _api = ApiClient();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.profile['full_name'] ?? '');
    _bandCtrl = TextEditingController(text: widget.profile['band_goal']?.toString() ?? '');
    _avatarUrl = widget.profile['avatar_url'] as String?;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bandCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final userId = Supa.currentUserId;
    if (userId == null) return;
    setState(() => _avatarUploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final path = '/$userId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await Supa.client.storage.from('avatars').uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
      final url = Supa.client.storage.from('avatars').getPublicUrl(path);
      setState(() => _avatarUrl = url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Avatar updated (save to apply).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final name = _nameCtrl.text.trim();
      final band = _bandCtrl.text.trim().isEmpty ? null : int.parse(_bandCtrl.text.trim());
      await _api.updateMe(fullName: name.isEmpty ? null : name, bandGoal: band, avatarPath: _avatarUrl);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = Supa.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                      child: _avatarUrl == null ? const Icon(Icons.person, size: 48) : null,
                    ),
                    if (_avatarUploading) const CircularProgressIndicator(),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(onPressed: _avatarUploading ? null : _pickAvatar, icon: const Icon(Icons.camera_alt_outlined), label: const Text('Change avatar')),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                readOnly: true,
                decoration: InputDecoration(labelText: 'Email', hintText: email),
                initialValue: email,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bandCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target band (1–9)'),
                validator: (v) {
                  if ((v ?? '').trim().isEmpty) return null;
                  final val = int.tryParse(v!.trim());
                  if (val == null || val < 1 || val > 9) return 'Enter 1–9';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save changes'),
          ),
        ),
      ),
    );
  }
}

