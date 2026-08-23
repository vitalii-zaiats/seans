import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:super_movies_api/super_movies_api.dart';

import '../data/web_proxy.dart';
import '../theme/nocturne.dart';

/// A remote image with a placeholder that holds the layout while it loads.
///
/// Every poster and backdrop goes through here, so the disk cache is shared —
/// a box scrolls the same rails every evening and should not refetch them.
class PosterImage extends StatelessWidget {
  const PosterImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
    this.placeholderIcon = Icons.movie_outlined,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius borderRadius;

  /// What stands in while the image loads, or instead of it. A film gets a
  /// clapperboard; a channel or an app wants something else, and the wrong
  /// glyph reads as a broken image rather than a missing one.
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(color: Nocturne.neutral900),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: context.px(40),
          color: Nocturne.neutral700,
        ),
      ),
    );

    // Anything the API serves itself comes back as a path, because the server
    // does not know what address it is reached on. Posters are the reason:
    // their own host sends no CORS header, so a browser loads one and then
    // paints nothing — the pixels taint the canvas.
    final resolved = url == null
        ? null
        : context.read<SuperMoviesApi>().resolve(url!);

    // On the web the image is fetched by the page, so it is subject to the
    // same origin rule as everything else.
    final source = WebProxy.forUrl(resolved);

    if (source == null) {
      return ClipRRect(borderRadius: borderRadius, child: placeholder);
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) => _image(context, source, constraints),
      ),
    );
  }

  /// The picture, decoded at the size it is drawn rather than the size it was
  /// sent.
  ///
  /// A poster arrives 640 wide and is painted about 200 — but it is decoded at
  /// full size, and a decoded frame is four bytes a pixel whatever the file
  /// weighed. That is 2.4 MB each, so five rails of them pass Flutter's 100 MB
  /// image cache, and past that images start coming back blank: a whole rail
  /// of black rectangles while the rails above it are fine.
  ///
  /// Asking for the drawn size instead cuts each one by about ten, and costs
  /// nothing — nobody can see detail that was never on screen.
  Widget _image(BuildContext context, String source, BoxConstraints size) {
    final width = size.hasBoundedWidth
        ? (size.maxWidth * MediaQuery.devicePixelRatioOf(context)).round()
        : null;

    final placeholder = DecoratedBox(
      decoration: const BoxDecoration(color: Nocturne.neutral900),
      child: Center(
        child: Icon(
          placeholderIcon,
          size: context.px(40),
          color: Nocturne.neutral700,
        ),
      ),
    );

    return kIsWeb
        // `CachedNetworkImage` fetches correctly and then loses the
        // pictures on the way back: they paint on first sight and come back
        // blank after leaving the screen and returning, which is the path
        // that reads what was cached rather than the one that fetches. Its
        // cache is a directory of files, and a browser has no directory to
        // give — `path_provider` has no web implementation.
        //
        // Nothing is lost by dropping the layer here. It is there for a box
        // that scrolls the same rails every evening; a browser has an HTTP
        // cache of its own, and the second look comes out of it without any
        // of this.
        ? Image.network(
            source,
            fit: fit,
            cacheWidth: width,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : placeholder,
            errorBuilder: (_, _, _) => placeholder,
          )
        : CachedNetworkImage(
            imageUrl: source,
            fit: fit,
            memCacheWidth: width,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          );
  }
}
