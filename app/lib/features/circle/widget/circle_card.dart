import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/time_format.dart';
import '../model/circle.dart';

/// 发现页圈子卡片（文档 3.4）：图标 / 名称 / 一句话简介 / 置顶角标 / 成员帖子数。
class CircleCard extends StatelessWidget {
  const CircleCard({super.key, required this.circle, this.onTap});

  final Circle circle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: circle.icon.isEmpty
                      ? Container(
                          color: scheme.primaryContainer,
                          alignment: Alignment.center,
                          child: Text(
                            circle.name.characters.first,
                            style: TextStyle(
                              fontSize: 18,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: circle.icon,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: scheme.surfaceContainerHighest),
                          errorWidget: (context, url, error) => Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.workspaces_outline,
                              color: scheme.outline,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            circle.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (circle.isOfficial) ...[
                          const SizedBox(width: 6),
                          _Tag(
                            text: '官方',
                            color: scheme.primary,
                            background: scheme.primary.withValues(alpha: .1),
                          ),
                        ],
                        if (circle.pinned) ...[
                          const SizedBox(width: 4),
                          const _Tag(
                            text: '置顶',
                            color: Color(0xFFE53E3E),
                            background: Color(0x1AE53E3E),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      circle.intro,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatCount(circle.memberCount)} 成员 · ${formatCount(circle.postCount)} 帖子',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (circle.joined)
                Text(
                  '已加入',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                )
              else
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.color,
    required this.background,
  });

  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
