import 'package:flutter/material.dart';

const waselBg = Color(0xFF080D16);
const waselPanel = Color(0xFF121B2A);
const waselPurple = Color(0xFF718CFF);
const waselCyan = Color(0xFF42D6C5);

/// A crisp surface component: readable on low-end phones without heavy blur.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.opacity = .78,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Color.lerp(waselPanel, const Color(0xFF1A2638), (opacity * .35).clamp(0, 1)),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: .075),
        width: 1,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x26000000),
          blurRadius: 20,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class GlowOrb extends StatelessWidget {
  const GlowOrb({super.key, required this.color, this.size = 190});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: .13), color.withValues(alpha: 0)],
        ),
      ),
    ),
  );
}

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(children: [
    const Positioned.fill(child: ColoredBox(color: waselBg)),
    const Positioned(top: -120, right: -120, child: GlowOrb(color: waselPurple, size: 310)),
    const Positioned(bottom: 40, left: -150, child: GlowOrb(color: waselCyan, size: 330)),
    Positioned.fill(child: child),
  ]);
}

class WaselAvatar extends StatelessWidget {
  const WaselAvatar({super.key, required this.label, this.online = false, this.size = 52});
  final String label;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF456DCE), Color(0xFF168E88)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Text(
        label.isEmpty ? 'و' : String.fromCharCode(label.runes.first),
        style: TextStyle(color: Colors.white, fontSize: size * .36, fontWeight: FontWeight.w800),
      ),
    ),
    if (online)
      Positioned(
        bottom: 1,
        right: 1,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: const Color(0xFF51E0A0),
            shape: BoxShape.circle,
            border: Border.all(color: waselBg, width: 2),
          ),
        ),
      ),
  ]);
}
