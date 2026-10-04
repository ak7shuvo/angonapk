import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/post.dart';

/// Photography-first media area: full-bleed, aspect ratio taken from the first
/// image (clamped to a calm range), swipeable when there are several items.
class PostMediaView extends StatefulWidget {
  const PostMediaView({super.key, required this.media});
  final List<PostMedia> media;

  @override
  State<PostMediaView> createState() => _PostMediaViewState();
}

class _PostMediaViewState extends State<PostMediaView> {
  int _index = 0;

  double get _aspect {
    final first = widget.media.first.aspectRatio ?? 4 / 3;
    return first.clamp(4 / 5, 16 / 10);
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    return AspectRatio(
      aspectRatio: _aspect,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (media.length == 1)
            _MediaTile(media: media.first)
          else
            PageView.builder(
              itemCount: media.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _MediaTile(media: media[i]),
            ),
          if (media.length > 1) ...[
            Positioned(
              top: 12,
              right: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    '${_index + 1}/${media.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < media.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: i == _index ? 0.95 : 0.6,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.media});
  final PostMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.type == MediaType.video) {
      return const _Placeholder(
        icon: Icons.play_circle_outline,
        label: 'Video playback is coming soon',
      );
    }
    return Semantics(
      image: true,
      label: media.altText ?? 'Photo',
      child: Image.network(
        media.url,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : const _Placeholder(),
        errorBuilder: (_, _, _) => const _Placeholder(
          icon: Icons.image_not_supported_outlined,
          label: 'Photo unavailable',
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.icon, this.label});
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? AppColors.nightCard : AppColors.paperDeep,
      child: icon == null
          ? null
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 36, color: AppColors.inkFaint),
                  if (label != null) ...[
                    const SizedBox(height: 8),
                    Text(label!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
    );
  }
}
