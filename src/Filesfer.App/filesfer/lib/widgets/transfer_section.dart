import 'package:filesfer/models/file_transfer.dart';
import 'package:filesfer/widgets/transfer_progress_tile.dart';
import 'package:flutter/material.dart';

class TransferSection extends StatelessWidget {
  const TransferSection({
    super.key,
    required this.title,
    required this.transfers,
    required this.color,
  });

  final String title;
  final List<FileTransfer> transfers;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                title == 'Uploads' ? Icons.upload_file : Icons.download_for_offline,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall!
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: transfers.length,
          itemBuilder: (context, index) {
            final transfer = transfers[index];
            return TransferProgressTile(transfer: transfer);
          },
        ),
      ],
    );
  }
}