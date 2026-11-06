import 'dart:ui';
import 'package:flutter/material.dart';

const waselBg = Color(0xFF07080D);
const waselPanel = Color(0xFF11131D);
const waselPurple = Color(0xFF9B7BFF);
const waselCyan = Color(0xFF55D6E8);

class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 24, this.opacity = .58, this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double opacity;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: opacity * .10),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: .13), width: 1),
          boxShadow: [BoxShadow(color: waselPurple.withValues(alpha: .07), blurRadius: 32, spreadRadius: -12)],
        ),
        child: child,
      ),
    ),
  );
}

class GlowOrb extends StatelessWidget {
  const GlowOrb({super.key, required this.color, this.size = 190});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => IgnorePointer(child: Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: .22), blurRadius: size * .55, spreadRadius: size * .08)]),
  ));
}

class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(children: [
    const Positioned.fill(child: ColoredBox(color: waselBg)),
    const Positioned(top: -105, right: -100, child: GlowOrb(color: waselPurple, size: 250)),
    const Positioned(bottom: 70, left: -130, child: GlowOrb(color: waselCyan, size: 240)),
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
    Container(width: size, height: size, alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [Color(0xFF57458D), Color(0xFF1B8797)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: Colors.white.withValues(alpha: .24)),
      ),
      child: Text(label.isEmpty ? 'و' : label.substring(0, 1), style: TextStyle(color: Colors.white, fontSize: size * .38, fontWeight: FontWeight.w800))),
    if (online) Positioned(bottom: 1, right: 1, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: const Color(0xFF51E0A0), shape: BoxShape.circle, border: Border.all(color: waselBg, width: 2)))),
  ]);
}
