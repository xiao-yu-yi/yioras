import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../model/circle.dart';

/// 圆形圈子图标：网络图 + 首字兜底（发现页/详情页/发布选择器共用）
class CircleIconAvatar extends StatelessWidget {
  const CircleIconAvatar({super.key, required this.circle, this.size = 44});

  final Circle circle;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: .08),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        circle.name.isEmpty ? '圈' : circle.name.characters.first,
        style: TextStyle(
          fontSize: size * .38,
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (circle.icon.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: circle.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (context, url) => fallback,
        errorWidget: (context, url, error) => fallback,
      ),
    );
  }
}
