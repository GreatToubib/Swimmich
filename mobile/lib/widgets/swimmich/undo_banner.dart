import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _currentEntry;

void showSwimmichUndoBanner(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
  Duration visible = const Duration(milliseconds: 2000),
  Duration fadeOut = const Duration(milliseconds: 200),
}) {
  final previous = _currentEntry;
  if (previous != null) {
    _removeEntry(previous);
  }

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _UndoBanner(
      message: message,
      onUndo: onUndo,
      onDismiss: () => _removeEntry(entry),
      visible: visible,
      fadeOut: fadeOut,
    ),
  );

  _currentEntry = entry;
  Overlay.of(context).insert(entry);
}

/// Removes [entry] only while it is still the current banner. A replaced banner
/// stays alive until the next frame, so its timer could otherwise fire and
/// remove its successor.
void _removeEntry(OverlayEntry entry) {
  if (!identical(_currentEntry, entry)) {
    return;
  }
  _currentEntry = null;
  entry.remove();
}

class _UndoBanner extends StatefulWidget {
  const _UndoBanner({
    required this.message,
    required this.onUndo,
    required this.onDismiss,
    required this.visible,
    required this.fadeOut,
  });

  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;
  final Duration visible;
  final Duration fadeOut;

  @override
  State<_UndoBanner> createState() => _UndoBannerState();
}

class _UndoBannerState extends State<_UndoBanner> {
  bool _fading = false;
  bool _dismissed = false;
  // Owned by this banner: a replaced banner is disposed one frame after its
  // successor's initState, so shared timers would be cancelled from under it.
  Timer? _fadeTimer;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    _fadeTimer = Timer(widget.visible, () {
      if (mounted) {
        setState(() => _fading = true);
      }
    });
    _removeTimer = Timer(widget.visible + widget.fadeOut, _remove);
  }

  void _remove() {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    widget.onDismiss();
  }

  void _handleUndo() {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    widget.onDismiss();
    widget.onUndo();
  }

  @override
  void dispose() {
    _fadeTimer?.cancel();
    _removeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 48,
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: _fading,
        child: AnimatedOpacity(
          opacity: _fading ? 0.0 : 1.0,
          duration: widget.fadeOut,
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF323232),
                borderRadius: BorderRadius.circular(4),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.message,
                    style: const TextStyle(color: Colors.white),
                  ),
                  TextButton(
                    onPressed: _handleUndo,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('UNDO'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
