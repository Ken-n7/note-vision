import 'package:flutter/material.dart';

class TappableButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;

  const TappableButton({super.key, required this.child, this.onPressed});

  @override
  State<TappableButton> createState() => _TappableButtonState();
}

class _TappableButtonState extends State<TappableButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // Announced as a button (with its child's text as the label), and as
    // disabled when there is nothing to do.
    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      child: GestureDetector(
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
      ),
    );
  }
}
