import 'package:filesfer/providers/file_transfer_notifier.dart';
import 'package:filesfer/screens/ip_input_screen.dart.dart';
import 'package:filesfer/services/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filesfer/providers/providers.dart';

class FileAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const FileAppBar({
    super.key,
    required this.isSelecting,
    required this.selectedFilesCount,
    required this.onClearSelection,
    required this.onDownloadMultipleFiles,
    required this.onOpenLastDownloadFolder,
  });

  final bool isSelecting;
  final int selectedFilesCount;
  final VoidCallback onClearSelection;
  final VoidCallback onDownloadMultipleFiles;
  final VoidCallback onOpenLastDownloadFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final viewMode = ref.watch(viewModeProvider);

    return AppBar(
      title: isSelecting
          ? Text('$selectedFilesCount selected')
          : RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.titleLarge,
                children: [
                  TextSpan(
                    text: 'Files',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  TextSpan(
                    text: 'fer',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
      leading: isSelecting
          ? IconButton(
              icon: const Icon(Icons.close),
              onPressed: onClearSelection,
            )
          : null,
      actions: isSelecting
          ? [
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: onDownloadMultipleFiles,
              ),
            ]
          : [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  switch (value) {
                    case 'theme':
                      ref.read(themeModeProvider.notifier).toggleTheme();
                      break;
                    case 'view':
                      ref.read(viewModeProvider.notifier).state = !viewMode;
                      break;
                    case 'open':
                      onOpenLastDownloadFolder();
                      break;
                    case 'ip_address':
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const IpInputScreen(isInitial: false),
                        ),
                      );
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'theme',
                    child: Row(
                      children: [
                        Icon(themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
                        const SizedBox(width: 8),
                        const Text('Toggle Theme'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(viewMode ? Icons.list : Icons.grid_view),
                        const SizedBox(width: 8),
                        const Text('Toggle View'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.folder_open),
                        SizedBox(width: 8),
                        Text('Open Downloads'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'ip_address',
                    child: Row(
                      children: [
                        Icon(Icons.settings_ethernet),
                        SizedBox(width: 8),
                        Text('Modify IP Address'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
      bottom: TabBar(
        controller: DefaultTabController.of(context),
        tabs: [
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open),
                SizedBox(width: 8),
                Text('Files'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (ref.watch(fileTransferNotifierProvider).isNotEmpty)
                  Badge(
                    label: Text(ref.watch(fileTransferNotifierProvider).length.toString()),
                    child: const Icon(Icons.sync_alt),
                  )
                else
                  const Icon(Icons.sync_alt),
                const SizedBox(width: 8),
                const Text('Transfers'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + kTextTabBarHeight);
}