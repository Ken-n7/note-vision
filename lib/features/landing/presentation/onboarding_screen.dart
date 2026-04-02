import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/user_profile_service.dart';
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
  bool _isLoading = false;

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
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    ));

    _animController.forward();
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _nameFocusNode.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    final error = NameValidator.validate(_nameController.text);
    setState(() => _nameError = error);
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
      setState(() => _selectedPhoto = File(image.path));
    } on PlatformException catch (e) {
      debugPrint('Image picker error: $e');
    } catch (e) {
      debugPrint('Unexpected image picker error: $e');
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

      await UserProfileService.saveProfile(name: name, photoPath: savedPhotoPath);

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CollectionScreen()),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
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
                    _buildAvatarSection(),
                    const SizedBox(height: 48),
                    _buildNameField(),
                    const SizedBox(height: 48),
                    _buildContinueButton(),
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
            color: const Color.fromARGB(255, 212, 169, 106), // Changed
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Welcome.',
          style: TextStyle(
            color: Color(0xFFF5F5F5),
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Let's set up your profile.\nThis takes less than a minute.",
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
            color: Color(0xFF555555),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            GestureDetector(
              onTap: _pickPhoto,
              child: Stack(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A1A1A),
                      border: Border.all(
                        color: _selectedPhoto != null
                            ? const Color.fromARGB(255, 212, 169, 106) // Changed
                            : const Color(0xFF2A2A2A),
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
                                      ? const Color.fromARGB(255, 212, 169, 106) // Changed
                                      : const Color(0xFF444444),
                                  fontSize: name.isNotEmpty ? 34 : 28,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (_selectedPhoto != null)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _removePhoto,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF2A2A2A),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Color(0xFF888888),
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                ],
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
                        color: Color.fromARGB(255, 212, 169, 106), // Changed
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Optional — you can skip this',
                    style: TextStyle(color: Color(0xFF555555), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNameField() {
    final hasError = _nameError != null && _nameController.text.isNotEmpty;
    final borderColor = hasError
        ? const Color(0xFFE05252)
        : _nameFocusNode.hasFocus
            ? const Color.fromARGB(255, 212, 169, 106).withOpacity(0.6) // Changed
            : const Color(0xFF2A2A2A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR NAME',
          style: TextStyle(
            color: Color(0xFF555555),
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
                color: Color(0xFF3A3A3A),
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
                  ? GestureDetector(
                      onTap: () {
                        _nameController.clear();
                        setState(() {});
                      },
                      child: const Icon(
                        Icons.cancel,
                        color: Color(0xFF444444),
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
                    color: Color(0xFFE05252),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _nameError!,
                    style: const TextStyle(
                      color: Color(0xFFE05252),
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
                color: hasError
                    ? const Color(0xFFE05252)
                    : const Color(0xFF555555),
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
            backgroundColor: const Color.fromARGB(255, 212, 169, 106), // Changed
            disabledBackgroundColor: const Color.fromARGB(255, 212, 169, 106), // Changed
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
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F0F0F)),
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
}