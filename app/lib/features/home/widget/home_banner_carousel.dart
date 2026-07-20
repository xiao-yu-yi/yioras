import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../model/home_config.dart';

/// 首页公告 Banner 轮播（文档 3.2）：大图卡自动轮播 + 指示点 + 可配跳转。
/// 两种卡面：
/// - 图文卡（含正文，如免责声明）：左侧文案 + 右侧配图，白色渐变保证可读性
/// - 纯图卡（仅标题）：全幅图 + 底部深色渐变 + 白字标题
class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({super.key, required this.banners});

  final List<HomeBanner> banners;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  final _pageController = PageController();
  Timer? _autoPlayTimer;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    if (widget.banners.length < 2) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_current + 1) % widget.banners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.banners.length,
            onPageChanged: (index) => setState(() => _current = index),
            itemBuilder: (context, index) =>
                _BannerCard(banner: widget.banners[index]),
          ),
          // 指示点悬浮在卡面右下角
          if (widget.banners.length > 1)
            Positioned(
              bottom: 22,
              right: 32,
              child: Row(
                children: [
                  for (var i = 0; i < widget.banners.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _current ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _current
                            ? scheme.primary
                            : Colors.white.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .15),
                            blurRadius: 3,
                          ),
                        ],
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

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final HomeBanner banner;

  void _onTap(BuildContext context) {
    // 后台可配跳转：1 帖子 3 圈子（2 H5 待 WebView 接入）
    switch (banner.linkType) {
      case 1:
        final postId = int.tryParse(banner.linkValue);
        if (postId != null) context.push(Routes.postDetailPath(postId));
      case 3:
        final circleId = int.tryParse(banner.linkValue);
        if (circleId != null) context.push(Routes.circleDetailPath(circleId));
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = banner.content.isNotEmpty;

    return GestureDetector(
      onTap: banner.linkType == 0 ? null : () => _onTap(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .07),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: hasContent
            ? _RichTextCard(banner: banner)
            : _ImageTitleCard(banner: banner),
      ),
    );
  }
}

/// 图文卡：右侧配图铺满，左向白渐变压图保证左侧长文案可读（贴原型免责声明卡）
class _RichTextCard extends StatelessWidget {
  const _RichTextCard({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner.image.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: .62,
              heightFactor: 1,
              child: CachedNetworkImage(
                imageUrl: banner.image,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    ColoredBox(color: scheme.surfaceContainerHighest),
              ),
            ),
          ),
        // 白渐变：左实右透，文字区域始终可读
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0, .48, .95],
              colors: [
                Colors.white,
                Colors.white.withValues(alpha: .96),
                Colors.white.withValues(alpha: .08),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                banner.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SizedBox(
                  // 文案只占左侧约 6 成，避免压到配图主体
                  width: MediaQuery.sizeOf(context).width * .56,
                  child: Text(
                    banner.content,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 6,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 纯图卡：全幅大图 + 底部深色渐变 + 白字标题（活动运营位）
class _ImageTitleCard extends StatelessWidget {
  const _ImageTitleCard({required this.banner});

  final HomeBanner banner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (banner.image.isNotEmpty)
          CachedNetworkImage(
            imageUrl: banner.image,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
            errorWidget: (context, url, error) => DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
            ),
          )
        else
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
            ),
          ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [.45, 1],
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Positioned(
          left: 18,
          right: 18,
          bottom: 16,
          child: Text(
            banner.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
