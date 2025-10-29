import { Component, DestroyRef, OnInit, inject, signal } from '@angular/core';
import { FileService } from './services/file.service';

import { CommonModule } from '@angular/common';
import { DownloadDialog } from './components/download-dialog/download-dialog';
import { FileItem } from './components/file-item/file-item';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, DownloadDialog, FileItem],
  templateUrl: './app.html',
  styleUrls: ['./app.css']
})
export class App implements OnInit {
  readonly title = signal('Filesfer');
  private readonly fileService = inject(FileService);
  private readonly destroyRef = inject(DestroyRef);

  files = signal<string[]>([]);
  activeDownload = signal<string | null>(null);
  isRefreshing = signal(false);
  isGridView = signal(true);

  ngOnInit(): void {
    this.loadFiles();
  }

  private loadFiles(): void {
    const sub = this.fileService.getFileList().subscribe({
      next: result => this.files.set(result ?? []),
      error: err => console.error('Failed to load files:', err)
    });
    this.destroyRef.onDestroy(() => sub.unsubscribe());
  }

  triggerRefresh(): void {
    this.isRefreshing.set(true);
    setTimeout(() => {
      this.loadFiles();
      this.isRefreshing.set(false);
    }, 800);
  }

  startDownload(filename: string): void {
    this.activeDownload.set(filename);
  }

  toggleViewMode() {
    this.isGridView.update(v => !v);
  }
}
