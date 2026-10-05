import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../models/place.dart';
import '../place_picker.dart';

/// "Tag a place" row used by the composer and the story editor.
class PlaceField extends StatelessWidget {
  const PlaceField({super.key, required this.place, required this.onChanged});
  final PlaceBrief? place;
  final ValueChanged<PlaceBrief?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final place = this.place;
    if (place == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final picked = await showPlacePicker(context);
            if (picked != null) onChanged(picked);
          },
          icon: const Icon(Icons.travel_explore_outlined),
          label: const Text('Tag a place'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 6, 6, 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          Icon(Icons.place, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              place.name,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Change place',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final picked = await showPlacePicker(context);
              if (picked != null) onChanged(picked);
            },
          ),
          IconButton(
            tooltip: 'Remove place',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => onChanged(null),
          ),
        ],
      ),
    );
  }
}
