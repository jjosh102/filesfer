import { Component, input, output } from '@angular/core';

@Component({
  selector: 'app-file-item',
  imports: [],
  templateUrl: './file-item.html',
  styleUrl: './file-item.css',
})
export class FileItem {
  filename = input<string>('');
  isGrid = input<boolean>(false);
  download = output<string>();

  get fileExtension(): string {
    const parts = this.filename().split('.');
    return parts.length > 1 ? parts.pop()!.toLowerCase() : '';
  }

  get icon(): string {
    const ext = this.fileExtension;
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].includes(ext)) return '🖼️';
    if (['mp4', 'avi', 'mkv'].includes(ext)) return '🎬';
    if (['mp3', 'wav', 'flac'].includes(ext)) return '🎵';
    if (['pdf'].includes(ext)) return '📄';
    if (['zip', 'rar', '7z'].includes(ext)) return '🗜️';
    if (['doc', 'docx'].includes(ext)) return '📘';
    if (['xls', 'xlsx'].includes(ext)) return '📊';
    if (['txt', 'md'].includes(ext)) return '📑';
    return '📁';
  }

  triggerDownload() {
    this.download.emit(this.filename());
  }
}
