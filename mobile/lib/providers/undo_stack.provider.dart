import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/sort_action.service.dart';

class UndoStackNotifier extends StateNotifier<List<UndoRecord>> {
  UndoStackNotifier() : super([]);
  static const _maxDepth = 10;

  void push(UndoRecord record) {
    state = [record, ...state].take(_maxDepth).toList();
  }

  UndoRecord? pop() {
    if (state.isEmpty) return null;
    final top = state.first;
    state = state.skip(1).toList();
    return top;
  }
}

final undoStackProvider =
    StateNotifierProvider<UndoStackNotifier, List<UndoRecord>>(
        (_) => UndoStackNotifier());
