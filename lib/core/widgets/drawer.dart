import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:note_vision/core/services/user_profile_service.dart';
import 'package:note_vision/core/widgets/user_avatar.dart';

class CollectionDrawer extends StatelessWidget {
  const CollectionDrawer({super.key});

  static const _bg            = Color(0xFF0D0D0D);
  static const _border        = Color(0xFF2C2C2C);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Drawer(
        backgroundColor: _bg,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            bottomLeft: Radius.circular(20),
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Profile header (stateful — reloads after edits) ──────
              const _ProfileHeader(),

              // ── Divider ──────────────────────────────────────────────
              Container(
                height: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: _border,
              ),

              const SizedBox(height: 12),

              // ── Section label ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
                child: Text(
                  'NAVIGATE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _textSecondary.withValues(alpha: 0.6),
                    letterSpacing: 2.0,
                  ),
                ),
              ),

              // ── Menu items ───────────────────────────────────────────
              _DrawerItem(
                icon: Icons.edit_outlined,
                title: 'Digital Writing',
                onTap: () => Navigator.pop(context),
              ),
              _DrawerItem(
                icon: Icons.school_outlined,
                title: 'Instruction',
                onTap: () => Navigator.pop(context),
              ),
              _DrawerItem(
                icon: Icons.info_outline,
                title: 'About',
                onTap: () => Navigator.pop(context),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Profile header (stateful so it reloads after edit sheet closes) ─────────

class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader();

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final profile = await UserProfileService.loadProfile();
    if (mounted) setState(() => _profile = profile);
  }

  Future<void> _onAvatarTap() async {
    final updated = await showModalBottomSheet<UserProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(profile: _profile),
    );

    if (updated != null) {
      // ✅ Instant update — no disk read needed
      if (mounted) setState(() => _profile = updated);
    } else {
      // User dismissed without saving — reload anyway just in case
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final name    = _profile?.name ?? '';
    final initial = _profile?.initial ?? '?';
    final photo   = _profile?.photoPath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tappable avatar with edit badge ──────────────────────────
          GestureDetector(
            onTap: _onAvatarTap,
            child: Stack(
              children: [
                UserAvatar(
                  initial: initial,
                  photoPath: photo,
                  size: 56,
                  borderColor: const Color(0xFF2C2C2C),
                  borderWidth: 2,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFD4A96A),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 10,
                      color: Color(0xFF0D0D0D),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (name.isNotEmpty) ...[
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'MaturaMTScriptCapitals',
                fontSize: 20,
                color: _textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
          ],

          Text(
            'Music sheet scanner',
            style: TextStyle(
              fontSize: 12,
              color: _textSecondary.withValues(alpha: 0.6),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit profile bottom sheet ────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final UserProfile? profile;

  const _EditProfileSheet({this.profile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const _bg      = Color(0xFF141414);
  static const _surface = Color(0xFF1E1E1E);
  static const _border  = Color(0xFF2C2C2C);
  static const _accent  = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  late final TextEditingController _nameController;
  final ImagePicker _picker = ImagePicker();

  File? _newPhoto;          // newly picked file, not yet persisted
  bool _clearPhoto = false; // user explicitly removed the existing photo
  bool _isSaving   = false;

  bool get _hasChanges {
    final nameChanged = _nameController.text.trim() != (widget.profile?.name ?? '');
    final photoChanged = _newPhoto != null || _clearPhoto;
    return nameChanged || photoChanged;
  }

  bool get _canSave =>
      _nameController.text.trim().length >= 1 && !_isSaving && _hasChanges;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() {
        _newPhoto   = File(image.path);
        _clearPhoto = false;
      });
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _removePhoto() => setState(() {
        _newPhoto   = null;
        _clearPhoto = true;
      });

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);

    try {
      final name = _nameController.text.trim();
      String? photoPath;

      if (_newPhoto != null) {
        // Copy new photo to permanent app documents directory
        final docsDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(_newPhoto!.path).isNotEmpty
            ? p.extension(_newPhoto!.path)
            : '.jpg';
        final dest = p.join(docsDir.path, 'profile_photo$ext');
        imageCache.evict(FileImage(File(dest)));
        await _newPhoto!.copy(dest);
        photoPath = dest;
      } else if (_clearPhoto) {
        photoPath = null; // saveProfile will remove the key
      } else {
        photoPath = widget.profile?.photoPath; // unchanged
      }

      await UserProfileService.saveProfile(name: name, photoPath: photoPath);

      if (mounted) {
        // ✅ Return the updated profile directly — no disk read needed
        Navigator.of(context).pop(
          UserProfile(name: name, photoPath: photoPath),
        );
      }
    } catch (e) {
      debugPrint('Profile save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Please try again.'),
            backgroundColor: Color(0xFF2A2A2A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String? get _displayPhotoPath =>
      _clearPhoto ? null : (_newPhoto?.path ?? widget.profile?.photoPath);

  String get _displayInitial {
    final name = _nameController.text.trim();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Handle bar ────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Edit Profile',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 24),

          // ── Avatar picker row ──────────────────────────────────────
          Row(
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    UserAvatar(
                      initial: _displayInitial,
                      photoPath: _displayPhotoPath,
                      size: 72,
                      borderColor: _accent.withValues(alpha: 0.4),
                      borderWidth: 2,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: _accent,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 12,
                          color: Color(0xFF0D0D0D),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton(
                    onPressed: _pickPhoto,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Change photo',
                      style: TextStyle(
                        color: _accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_displayPhotoPath != null) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _removePhoto,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Remove photo',
                        style: TextStyle(
                          color: _textSecondary.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Name field ─────────────────────────────────────────────
          const Text(
            'NAME',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.8,
            ),
          ),

          const SizedBox(height: 10),

          Container(
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: TextField(
              controller: _nameController,
              maxLength: 30,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(
                color: _textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: 'Your name',
                hintStyle:
                    TextStyle(color: _textSecondary.withValues(alpha: 0.4)),
                counterText: '',
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixText: '${_nameController.text.trim().length}/30',
                suffixStyle: const TextStyle(
                  color: _textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Save button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 50,
            child: AnimatedOpacity(
              opacity: _canSave ? 1.0 : 0.4,
              duration: const Duration(milliseconds: 150),
              child: ElevatedButton(
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor: _accent,
                  foregroundColor: const Color(0xFF0D0D0D),
                  disabledForegroundColor: const Color(0xFF0D0D0D),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF0D0D0D),
                          ),
                        ),
                      )
                    : const Text(
                        'Save changes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Drawer item ──────────────────────────────────────────────────────────────

class _DrawerItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  State<_DrawerItem> createState() => _DrawerItemState();
}

class _DrawerItemState extends State<_DrawerItem> {
  bool _hovered = false;

  static const _surface       = Color(0xFF1A1A1A);
  static const _accent        = Color(0xFFD4A96A);
  static const _textPrimary   = Color(0xFFFFFFFF);
  static const _textSecondary = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: _hovered ? _surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _hovered
                    ? _accent.withValues(alpha: 0.15)
                    : const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                widget.icon,
                size: 18,
                color: _hovered ? _accent : _textSecondary,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              widget.title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _hovered ? _textPrimary : _textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}