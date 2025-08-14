import 'package:filesfer/providers/file_transfer_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filesfer/models/file_transfer.dart';

class TransferProgressTile extends ConsumerWidget {
  final FileTransfer transfer;

  const TransferProgressTile({super.key, required this.transfer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    IconData icon;
    Color color;
    String statusText;

    switch (transfer.status) {
      case TransferStatus.inProgress:
        icon = Icons.sync_rounded;
        color = Colors.blue;
        statusText =
            '${(transfer.progress * 100).toStringAsFixed(1)}% - In Progress';
        break;
      case TransferStatus.completed:
        icon = Icons.check_circle_outline;
        color = Colors.green;
        statusText = 'Completed';
        break;
      case TransferStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red;
        statusText = 'Failed: ${transfer.errorMessage}';
        break;
      case TransferStatus.cancelled:
        icon = Icons.cancel_outlined;
        color = Colors.orange;
        statusText = 'Cancelled';
        break;
      case TransferStatus.pending:
        icon = Icons.timer_outlined;
        color = Colors.grey;
        statusText = 'Pending';
        break;
    }

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        transfer.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: LinearProgressIndicator(
        value: transfer.status == TransferStatus.inProgress ||
                transfer.status == TransferStatus.pending
            ? transfer.progress
            : 1.0,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        backgroundColor: color.withValues(alpha: 0.2),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(statusText, style: TextStyle(color: color, fontSize: 12)),
          if (transfer.status == TransferStatus.inProgress)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                ref
                    .read(fileTransferNotifierProvider.notifier)
                    .cancelTransfer(transfer.id);
              },
            ),
          if (transfer.status == TransferStatus.completed ||
              transfer.status == TransferStatus.failed ||
              transfer.status == TransferStatus.cancelled)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                ref
                    .read(fileTransferNotifierProvider.notifier)
                    .removeTransfer(transfer.id);
              },
            ),
        ],
      ),
    );
  }
}