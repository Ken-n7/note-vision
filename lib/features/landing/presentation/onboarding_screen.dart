import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/app_features.dart';
import '../../../core/services/user_profile_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/name_validator.dart';
import '../../collection/presentation/collection_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  File? _selectedPhoto;
  String? _photoError;
  Timer? _photoErrorTimer;
  bool _isLoading = false;
  bool _showRoleStep = false;

  // Validation state
  String? _nameError;
  bool get _isContinueEnabled =>
      _nameError == null &&
      _nameController.text.trim().isNotEmpty &&
      !_isLoading;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_onNameChanged);
    _nameFocusNode.addListener(() => setState(() {}));

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animController,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
          ),
        );

    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _nameFocusNode.dispose();
    _animController.dispose();
    _photoErrorTimer?.cancel();
    super.dispose();
  }

  void _onNameChanged() {
    final error = NameValidator.validate(_nameController.text);
    setState(() => _nameError = error);
  }

  void _showPhotoError(String message) {
    _photoErrorTimer?.cancel();
    setState(() => _photoError = message);
    _photoErrorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _photoError = null);
    });
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
      final ext = image.path.contains('.')
          ? image.path.substring(image.path.lastIndexOf('.')).toLowerCase()
          : '';
      const supported = {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'};
      if (!supported.contains(ext)) {
        if (mounted) _showPhotoError('Unsupported format. Use JPG, PNG, or WebP.');
        return;
      }
      setState(() {
        _selectedPhoto = File(image.path);
        _photoError = null;
        _photoErrorTimer?.cancel();
      });
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
      if (mounted) _showPhotoError('Could not access photos. Check app permissions.');
    } catch (e) {
      debugPrint('Unexpected image picker error: $e');
      if (mounted) _showPhotoError('Failed to pick photo. Please try again.');
    }
  }

  void _removePhoto() => setState(() => _selectedPhoto = null);

  Future<void> _onContinue() async {
    if (!_isContinueEnabled) return;
    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      String? savedPhotoPath;

      if (_selectedPhoto != null) {
        final docsDir = await getApplicationDocumentsDirectory();
        final ext = p.extension(_selectedPhoto!.path).isNotEmpty
            ? p.extension(_selectedPhoto!.path)
            : '.jpg';
        final destPath = p.join(docsDir.path, 'profile_photo$ext');
        await _selectedPhoto!.copy(destPath);
        savedPhotoPath = destPath;
      }

      await UserProfileService.saveProfile(
        name: name,
        photoPath: savedPhotoPath,
        completeOnboarding: !AppFeatures.classroomWorkflow,
      );

      if (!mounted) return;
      if (!AppFeatures.classroomWorkflow) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const CollectionScreen()),
        );
        return;
      }
      setState(() => _showRoleStep = true);
    } catch (e) {
      debugPrint('Onboarding save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Color(0xFF2A2A2A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onRoleSelected(String role) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await UserProfileService.saveRole(role);
      await UserProfileService.markOnboardingComplete();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CollectionScreen()),
      );
    } catch (e) {
      debugPrint('Role save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Color(0xFF2A2A2A),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 64),
                    _buildHeader(),
                    const SizedBox(height: 56),
                    if (AppFeatures.classroomWorkflow && _showRoleStep)
                      _buildRoleStep()
                    else ...[
                      _buildAvatarSection(),
                      const SizedBox(height: 48),
                      _buildNameField(),
                      const SizedBox(height: 48),
                      _buildContinueButton(),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          AppFeatures.classroomWorkflow && _showRoleStep
              ? 'Choose your role.'
              : 'Welcome.',
          style: TextStyle(
            color: Color(0xFFF5F5F5),
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppFeatures.classroomWorkflow && _showRoleStep
              ? 'This stays with this installation.\nOnly reinstalling the app resets it.'
              : "Let's set up your profile.\nThis takes less than a minute.",
          style: TextStyle(
            color: Color(0xFF888888),
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.55,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarSection() {
    final name = _nameController.text.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PROFILE PHOTO',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Semantics(
              button: true,
              label: _selectedPhoto != null
                  ? 'Profile photo. Tap to change'
                  : 'Add a profile photo',
              child: GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A1A1A),
                      border: Border.all(
                        color: _selectedPhoto != null
                            ? AppColors.accent
                            : AppColors.border,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: _selectedPhoto != null
                          ? Image.file(
                              _selectedPhoto!,
                              fit: BoxFit.cover,
                              width: 88,
                              height: 88,
                            )
                          : Center(
                              child: Text(
                                name.isNotEmpty ? initial : '+',
                                style: TextStyle(
                                  color: name.isNotEmpty
                                      ? AppColors.accent
                                      : AppColors.textSecondary,
                                  fontSize: name.isNotEmpty ? 34 : 28,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (_selectedPhoto != null)
                    Positioned(
                      bottom: -10,
                      right: -10,
                      // A 44 px touch area around the small round button.
                      child: Semantics(
                        button: true,
                        label: 'Remove photo',
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _removePhoto,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.surface,
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: AppColors.textSecondary,
                                  size: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton(
                    onPressed: _pickPhoto,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _selectedPhoto != null
                          ? 'Change photo'
                          : 'Choose from gallery',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Optional — you can skip this',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_photoError != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 13, color: AppColors.error),
              const SizedBox(width: 4),
              Text(
                _photoError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNameField() {
    final hasError = _nameError != null && _nameController.text.isNotEmpty;
    final borderColor = hasError
        ? AppColors.error
        : _nameFocusNode.hasFocus
        ? AppColors.accent.withValues(alpha: 0.6)
        : const Color(0xFF2A2A2A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR NAME',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 12),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: TextField(
            controller: _nameController,
            focusNode: _nameFocusNode,
            maxLength: NameValidator.maxLength,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [NameValidator.inputFormatter],
            style: const TextStyle(
              color: Color(0xFFF5F5F5),
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
            decoration: InputDecoration(
              hintText: 'Enter your name',
              hintStyle: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w400,
              ),
              counterText: '',
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              suffixIcon: _nameController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear name',
                      onPressed: () {
                        _nameController.clear();
                        setState(() {});
                      },
                      icon: const Icon(
                        Icons.cancel,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),

        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (hasError)
              Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 13,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _nameError!,
                    style: const TextStyle(
                      color: AppColors.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              )
            else
              const SizedBox.shrink(),

            Text(
              '${_nameController.text.trim().length} / ${NameValidator.maxLength}',
              style: TextStyle(
                color: hasError ? AppColors.error : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: AnimatedOpacity(
        opacity: _isContinueEnabled ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 200),
        child: ElevatedButton(
          onPressed: _isContinueEnabled ? _onContinue : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            disabledBackgroundColor: AppColors.accent,
            foregroundColor: const Color(0xFF0F0F0F),
            disabledForegroundColor: const Color(0xFF0F0F0F),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF0F0F0F),
                    ),
                  ),
                )
              : const Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildRoleStep() {
    return Column(
      children: [
        _RoleCard(
          icon: Icons.school_rounded,
          title: 'I am a Student',
          subtitle: 'Create scores and submit them to a teacher.',
          isLoading: _isLoading,
          onTap: () => _onRoleSelected('student'),
        ),
        const SizedBox(height: 14),
        _RoleCard(
          icon: Icons.workspace_premium_rounded,
          title: 'I am a Teacher',
          subtitle: 'Import, review, and export student submissions.',
          isLoading: _isLoading,
          onTap: () => _onRoleSelected('teacher'),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedOpacity(
        opacity: isLoading ? 0.55 : 1,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
