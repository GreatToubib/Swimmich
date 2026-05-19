import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SortSource { newAssets, reviewLater }

/// Which source albums the sort queue pulls from.
/// Defaults to both — all unsorted photos appear.
final sortSourceFilterProvider = StateProvider<Set<SortSource>>(
  (_) => {SortSource.newAssets, SortSource.reviewLater},
);
