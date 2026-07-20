import 'package:flutter/material.dart';

/// 虚线圆角边框绘制器（发布器「添加图片/上传 Logo」占位框）
class DashedRectPainter extends CustomPainter {
  DashedRectPainter({
    required this.color,
    this.radius = 12,
    this.strokeWidth = 1.2,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedRectPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// 虚线添加框：+ 图标 + 文案（图片/Logo 上传入口通用）
class DashedAddBox extends StatelessWidget {
  const DashedAddBox({
    super.key,
    required this.enabled,
    required this.onTap,
    required this.icon,
    required this.label,
  });

  final bool enabled;
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: CustomPaint(
        painter: DashedRectPainter(
          color: scheme.outlineVariant.withValues(alpha: .9),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: scheme.onSurfaceVariant),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
