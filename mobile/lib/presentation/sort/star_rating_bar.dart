import 'package:flutter/material.dart';

/// Six-icon rating bar shown on the bottom-right of each sort card.
///
/// Icons: Meh (no rating) | 1★ | 2★ | 3★ | 4★ | 5★
/// Tapping Meh resets to 0; tapping star N sets rating to N.
/// Stars ≤ rating are filled; stars > rating show only a border.
/// The rating is written to the asset's native metadata (xmp:Rating).
class StarRatingBar extends StatelessWidget {
  const StarRatingBar({
    super.key,
    required this.rating,
    required this.onChanged,
  });

  final int rating; // 0 = none, 1–5 = star count
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Meh — resets rating to 0.
          GestureDetector(
            onTap: () => onChanged(0),
            child: Icon(
              Icons.sentiment_neutral_rounded,
              size: 26,
              color: rating == 0 ? primary : onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(width: 4),
          // Stars 1–5.
          for (int i = 1; i <= 5; i++) ...[
            GestureDetector(
              onTap: () => onChanged(i),
              child: Icon(
                i <= rating ? Icons.star_rounded : Icons.star_border_rounded,
                size: 26,
                color: i <= rating ? Colors.amber : onSurface.withValues(alpha: 0.5),
              ),
            ),
            if (i < 5) const SizedBox(width: 2),
          ],
        ],
      ),
    );
  }
}
