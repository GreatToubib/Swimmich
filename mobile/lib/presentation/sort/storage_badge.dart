import 'package:flutter/material.dart';
import 'package:openapi/api.dart';

class StorageBadge extends StatelessWidget {
  const StorageBadge({super.key, required this.asset});

  final AssetResponseDto asset;

  @override
  Widget build(BuildContext context) {
    final isOffline = asset.isOffline;
    final icon =
        isOffline ? Icons.cloud_off_outlined : Icons.cloud_outlined;
    final tooltip = isOffline
        ? 'File not reachable on server'
        : 'Stored in cloud – left-swipe sends to Immich trash';

    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.longPress,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}
