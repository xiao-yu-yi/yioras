import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 全屏图片预览：左右滑动切换 + 双指缩放，点击空白关闭（文档 3.3 点击大图预览）。
/// 保存到相册依赖存储权限，随 M2 后续版本接入。
Future<void> showImageGallery(
  BuildContext context, {
  required List<String> images,
  int initialIndex = 0,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    useSafeArea: false,
    builder: (context) =>
        _GalleryView(images: images, initialIndex: initialIndex),
  );
}

class _GalleryView extends StatefulWidget {
  const _GalleryView({required this.images, required this.initialIndex});

  final List<String> images;
  final int initialIndex;

  @override
  State<_GalleryView> createState() => _GalleryViewState();
}

class _GalleryViewState extends State<_GalleryView> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _current = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: widget.images.length,
          onPageChanged: (index) => setState(() => _current = index),
          itemBuilder: (context, index) => GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: widget.images[index],
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white54,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white38,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 页码指示
        Positioned(
          top: MediaQuery.paddingOf(context).top + 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_current + 1}/${widget.images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
