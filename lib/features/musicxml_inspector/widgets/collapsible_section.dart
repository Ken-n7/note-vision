import 'package:flutter/material.dart';

class CollapsibleSection extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget? child;

  const CollapsibleSection({
    super.key,
    required this.label,
    required this.enabled,
    required this.expanded,
    this.onToggle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8), width: 0.5),
        ),
        child: Column(
          children: [
            GestureDetector(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF999999),
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      expanded ? 'Hide ▴' : 'Show ▾',
                      style: TextStyle(
                        fontSize: 11,
                        color: enabled
                            ? const Color(0xFF185FA5)
                            : const Color(0xFFBBBBBB),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded && child != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
                child: child!,
              ),
          ],
        ),
      ),
    );
  }
}
