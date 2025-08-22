import 'package:flutter/material.dart';

class FileListView extends StatelessWidget {
  const FileListView({
    super.key,
    required this.files,
    required this.selectedFiles,
    required this.onToggleSelection,
    required this.onDownloadSingleFile,
    required this.getFileIcon,
  });

  final List<String> files;
  final Set<String> selectedFiles;
  final Function(String) onToggleSelection;
  final Function(String) onDownloadSingleFile;
  final Function(String) getFileIcon;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: files.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final filename = files[index];
        final isSelected = selectedFiles.contains(filename);
        return ListTile(
          onTap: () => onToggleSelection(filename),
          leading: isSelected
              ? const Icon(Icons.check_circle, color: Colors.blue)
              : Icon(getFileIcon(filename) as IconData),
          title: Text(filename),
          trailing: IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => onDownloadSingleFile(filename),
          ),
        );
      },
    );
  }
}