import 'package:flutter/material.dart';

class FileGridView extends StatelessWidget {
  const FileGridView({
    super.key,
    required this.files,
    required this.selectedFiles,
    required this.onToggleSelection,
    required this.getFileIcon,
  });

  final List<String> files;
  final Set<String> selectedFiles;
  final Function(String) onToggleSelection;
  final Function(String) getFileIcon;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: files.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final filename = files[index];
        final isSelected = selectedFiles.contains(filename);
        return Card(
          color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
          child: InkWell(
            onTap: () => onToggleSelection(filename),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    getFileIcon(filename) as IconData,
                    size: 36,
                    color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    filename,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isSelected ? Theme.of(context).colorScheme.onPrimaryContainer : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}