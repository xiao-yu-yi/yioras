import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/time_format.dart';
import '../data/software_repository.dart';
import '../model/software.dart';
import 'software_comments_section.dart';

/// 软件详情数据源（family：软件 ID）
final softwareDetailProvider = FutureProvider.autoDispose
    .family<SoftwareDetail, int>((ref, id) {
      return ref.watch(softwareRepositoryProvider).fetchDetail(id);
    });

/// 软件详情页（文档 3.6）：Logo/名称/版本/大小/渠道/标签 + 介绍图横滑 +
/// 简介 + 发布者 + 历史版本 + 底部下载（非官方渠道风险弹窗 + 免责声明）。
class SoftwareDetailPage extends ConsumerWidget {
  const SoftwareDetailPage({super.key, required this.softwareId});

  final int softwareId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(softwareDetailProvider(softwareId));

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text(
          '软件详情',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: switch (detail) {
        AsyncData(:final value) => _DetailBody(detail: value),
        AsyncError(:final error) => _ErrorView(
          message: error is ApiException ? error.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(softwareDetailProvider(softwareId)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.detail});

  final SoftwareDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = detail.item;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
            children: [
              _HeaderCard(item: item),
              const SizedBox(height: 10),
              if (detail.images.isNotEmpty) ...[
                _SectionCard(
                  title: '软件截图',
                  child: _ScreenshotStrip(images: detail.images),
                ),
                const SizedBox(height: 10),
              ],
              _SectionCard(
                title: '软件简介',
                child: Text(
                  item.intro,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.7,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .85),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _SectionCard(
                title: '发布者',
                child: _PublisherRow(publisher: detail.publisher),
              ),
              if (detail.versions.isNotEmpty) ...[
                const SizedBox(height: 10),
                _SectionCard(
                  title: '版本记录',
                  child: Column(
                    children: [
                      for (var i = 0; i < detail.versions.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 16,
                            thickness: .5,
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: .4),
                          ),
                        _VersionRow(
                          softwareId: item.id,
                          version: detail.versions[i],
                          latest: i == 0,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // 评论区（文档 3.6）
              SoftwareCommentsSection(softwareId: item.id),
              // 免责声明（文档 3.6 安全提示）
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(
                  '本平台仅提供信息存储与分享，软件版权归原作者所有。'
                  '请勿下载使用侵权内容，下载即代表你已知晓并同意《免责声明》。',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        _DownloadBar(detail: detail),
      ],
    );
  }
}

/// 头卡：Logo + 名称 + 版本/大小/下载数 + 标签
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.item});

  final SoftwareItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 68,
              height: 68,
              child: item.logo.isEmpty
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(Icons.android, color: scheme.outline),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.logo,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) =>
                          Container(color: scheme.surfaceContainerHighest),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    if (item.version.isNotEmpty) 'v${item.version}',
                    if (item.size.isNotEmpty) item.size,
                    '${formatCount(item.downloadCount)} 次下载',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (item.tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final tag in item.tags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFF43F5E,
                            ).withValues(alpha: .07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFFF43F5E),
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 介绍图横滑条（点击看大图交给系统图片查看惯例，此处保持轻量）
class _ScreenshotStrip extends StatelessWidget {
  const _ScreenshotStrip({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 9 / 16,
            child: CachedNetworkImage(
              imageUrl: images[index],
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: scheme.surfaceContainerHighest),
              errorWidget: (context, url, error) =>
                  Container(color: scheme.surfaceContainerHighest),
            ),
          ),
        ),
      ),
    );
  }
}

class _PublisherRow extends StatelessWidget {
  const _PublisherRow({required this.publisher});

  final SoftwarePublisher publisher;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: publisher.id > 0
          ? () => context.push(Routes.userProfilePath(publisher.id))
          : null,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundImage: publisher.avatar.isEmpty
                ? null
                : CachedNetworkImageProvider(publisher.avatar),
            child: Text(
              publisher.nickname.isEmpty
                  ? '?'
                  : publisher.nickname.characters.first,
              style: TextStyle(fontSize: 13, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  publisher.nickname,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Lv.${publisher.level} 认证发布者',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: scheme.outline),
        ],
      ),
    );
  }
}

/// 版本行：版本号/渠道/大小/时间 + 下载按钮（旧版本也可下载）
class _VersionRow extends ConsumerWidget {
  const _VersionRow({
    required this.softwareId,
    required this.version,
    required this.latest,
  });

  final int softwareId;
  final SoftwareVersion version;
  final bool latest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'v${version.version}',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (latest) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF43F5E).withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        '最新',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFFF43F5E),
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (version.channel.isNotEmpty) version.channel,
                  if (version.size.isNotEmpty) version.size,
                  formatRelativeTime(version.createdAt),
                ].join(' · '),
                style: TextStyle(fontSize: 11.5, color: scheme.outline),
              ),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => startSoftwareDownload(
            context,
            ref,
            softwareId: softwareId,
            versionId: version.id,
            channel: version.channel,
          ),
          child: const Text('下载'),
        ),
      ],
    );
  }
}

/// 底部下载栏：渐变主按钮（最新版）
class _DownloadBar extends ConsumerWidget {
  const _DownloadBar({required this.detail});

  final SoftwareDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = detail.versions.isEmpty ? null : detail.versions.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 46,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF43F5E), Color(0xFFFF7849)],
              ),
              borderRadius: BorderRadius.circular(23),
            ),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(23),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: latest == null
                  ? null
                  : () => startSoftwareDownload(
                      context,
                      ref,
                      softwareId: detail.item.id,
                      versionId: 0,
                      channel: latest.channel,
                    ),
              child: Text(
                latest == null
                    ? '暂无可下载版本'
                    : '下载最新版 v${latest.version}'
                          '${detail.item.size.isEmpty ? '' : '（${detail.item.size}）'}',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 发起下载：非官方渠道先弹风险确认（文档 3.6 安全提示），
/// 确认后调下载接口计数并展示链接/提取码（一期跳转浏览器由链接承载，这里提供复制）。
Future<void> startSoftwareDownload(
  BuildContext context,
  WidgetRef ref, {
  required int softwareId,
  required int versionId,
  required String channel,
}) async {
  // 非官方渠道风险弹窗
  if (channel != '官方') {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('下载风险提示'),
        content: Text(
          '该资源来自${channel.isEmpty ? '第三方' : '「$channel」'}渠道，'
          '非官方发布。请注意甄别安装包安全性，谨防诈骗与恶意软件；'
          '因下载使用产生的风险由用户自行承担。',
          style: const TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('知晓风险，继续下载'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
  }

  try {
    final download = await ref
        .read(softwareRepositoryProvider)
        .resolveDownload(softwareId, versionId: versionId);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => _DownloadResultSheet(download: download),
    );
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('获取下载链接失败：${e.message}')));
    }
  }
}

/// 下载链接结果面板：链接 + 提取码（可一键复制）
class _DownloadResultSheet extends StatelessWidget {
  const _DownloadResultSheet({required this.download});

  final SoftwareDownload download;

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$label已复制')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '开始下载 v${download.version}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '复制链接到浏览器或网盘客户端完成下载',
              style: TextStyle(fontSize: 12.5, color: scheme.outline),
            ),
            const SizedBox(height: 14),
            _CopyRow(
              label: '下载链接',
              value: download.downloadUrl,
              onCopy: () => _copy(context, download.downloadUrl, '下载链接'),
            ),
            if (download.extractCode.isNotEmpty) ...[
              const SizedBox(height: 8),
              _CopyRow(
                label: '提取码',
                value: download.extractCode,
                onCopy: () => _copy(context, download.extractCode, '提取码'),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: onCopy,
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_outlined, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
        ],
      ),
    );
  }
}

/// 白卡分区
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
