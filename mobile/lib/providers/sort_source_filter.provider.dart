import 'package:hooks_riverpod/hooks_riverpod.dart';

enum SortSource { newAssets, reviewLater }

/// Which single source album the sort queue pulls from.
///
/// Mutually exclusive — the queue shows either New OR Review Later, never both.
/// (Immich's metadata search treats multiple albumIds as an intersection/AND,
/// so combining them would only ever return assets present in every album.)
final sortSourceFilterProvider = StateProvider<SortSource>(
  (_) => SortSource.newAssets,
);
