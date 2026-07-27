import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_dialog.dart';
import 'package:immich_mobile/widgets/common/user_circle_avatar.dart';

/// Swimmich-owned app bar for the Sort page.
///
/// Upstream v3 deleted `ImmichAppBar` and replaced it with the sliver-based
/// `ImmichSliverAppBar`. That one cannot be used here: `SortPage`'s body is a
/// fixed-height `Column` (swipe deck + quick-pick row), not a scroll view, so a
/// sliver has nothing to attach to. Restructuring the page into a
/// `CustomScrollView` would also risk gesture conflicts with the swipe deck.
///
/// This is deliberately a plain `PreferredSizeWidget` so `SortPage` keeps its
/// `Scaffold(appBar:)` structure untouched, and deliberately fork-owned so it
/// never conflicts with upstream again.
///
/// Backup and cast indicators are intentionally omitted — sorting is not a
/// backup surface, and they would pull in several more upstream providers.
class SortAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const SortAppBar({super.key, this.actions = const []});

  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return AppBar(
      title: SvgPicture.asset(
        context.isDarkTheme ? 'assets/immich-logo-inline-dark.svg' : 'assets/immich-logo-inline-light.svg',
        height: 40,
      ),
      actions: [
        ...actions,
        if (user != null)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => showDialog(
                context: context,
                useRootNavigator: false,
                builder: (_) => const ImmichAppBarDialog(),
              ),
              child: UserCircleAvatar(user: user, size: 32),
            ),
          ),
      ],
    );
  }
}
