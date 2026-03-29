import 'package:flutter/material.dart';

class ScanActions extends StatelessWidget {
  final VoidCallback onRedo;
  final VoidCallback onContinue;
  final VoidCallback? onImport;
  final bool canContinue;

  const ScanActions({
    super.key,
    required this.onRedo,
    required this.onContinue,
    this.onImport,
    this.canContinue = true,
  });

  static const _bg = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF1A1A1A);
  static const _border = Color(0xFF2C2C2C);
  static const _accent = Color(0xFFD4A96A);
  static const _textPrimary = Color(0xFFFFFFFF);
  static const _textMuted = Color(0xFF8A8A8A);

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final stackButtons = isLandscape && onImport != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border, width: 0.5)),
      ),
      child: stackButtons
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildRedoButton()),
                    const SizedBox(width: 12),
                    Expanded(child: _buildImportButton()),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: _buildContinueButton(flex: 1)),
              ],
            )
          : Row(
              children: [
                Expanded(child: _buildRedoButton()),
                const SizedBox(width: 12),
                if (onImport != null) ...[
                  Expanded(child: _buildImportButton()),
                  const SizedBox(width: 12),
                ],
                _buildContinueButton(flex: onImport == null ? 2 : 1),
              ],
            ),
    );
  }

  Widget _buildRedoButton() {
    return _TappableButton(
      onPressed: onRedo,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.redo_outlined, size: 18, color: _textMuted),
            SizedBox(width: 8),
            Text(
              'Redo',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _textMuted,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() {
    return _TappableButton(
      onPressed: onImport,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.file_upload_outlined, size: 18, color: _textMuted),
            SizedBox(width: 8),
            Text(
              'Import',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _textMuted,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton({required int flex}) {
    return Expanded(
      flex: flex,
      child: _TappableButton(
        onPressed: canContinue ? onContinue : null,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: canContinue ? _textPrimary : _border,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Continue',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: canContinue ? _bg : _textMuted,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward,
                size: 18,
                color: canContinue ? _bg : _textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TappableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const _TappableButton({required this.child, required this.onPressed});

  @override
  State<_TappableButton> createState() => _TappableButtonState();
}

class _TappableButtonState extends State<_TappableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onPressed == null ? null : () => setState(() => _pressed = false),
      onTap: widget.onPressed == null
          ? null
          : () {
              setState(() => _pressed = false);
              widget.onPressed!();
            },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: widget.child,
        ),
      ),
    );
  }
}
