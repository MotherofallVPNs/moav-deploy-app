import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A monochrome brand mark (Simple Icons, CC0) drawn like an [Icon]: tinted
/// with the ambient [IconTheme] so it follows the surrounding row.
class BrandIcon extends StatelessWidget {
  const BrandIcon(this.asset, {super.key, this.size = 22, this.color});

  static const github = 'assets/brand/github.svg';
  static const x = 'assets/brand/x.svg';
  static const telegram = 'assets/brand/telegram.svg';

  final String asset;
  final double size;

  /// Overrides the [IconTheme] colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ??
        IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
  }
}
