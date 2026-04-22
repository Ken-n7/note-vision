import 'package:flutter/material.dart';
import 'package:note_vision/core/theme/app_theme.dart';

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  static const routeName = '/instructions';

  static const _steps = [
    _Step(
      icon: Icons.camera_alt_outlined,
      title: 'Scan',
      description:
          'Take a photo of sheet music using your camera, or import an image from your gallery.',
    ),
    _Step(
      icon: Icons.playlist_add_check_outlined,
      title: 'Review Detections',
      description:
          'Check the detected notes and symbols. Confirm the results look correct before continuing.',
    ),
    _Step(
      icon: Icons.edit_outlined,
      title: 'Edit the Score',
      description:
          'Use the editor to correct notes, adjust pitches and durations, add accidentals, or insert and delete symbols.',
    ),
    _Step(
      icon: Icons.play_circle_outline_rounded,
      title: 'Play Back',
      description:
          'Play back the score to verify it sounds as expected. Adjust tempo as needed.',
    ),
    _Step(
      icon: Icons.download_outlined,
      title: 'Export',
      description:
          'Export the finished score as a PDF for printing, or as MusicXML to open in notation software.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'How to Use',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        itemCount: _steps.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _StepCard(
          step: index + 1,
          data: _steps[index],
        ),
      ),
    );
  }
}

class _Step {
  final IconData icon;
  final String title;
  final String description;

  const _Step({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.data});

  final int step;
  final _Step data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(data.icon, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accent.withValues(alpha: 0.2),
                      ),
                      child: Center(
                        child: Text(
                          '$step',
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      data.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  data.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
