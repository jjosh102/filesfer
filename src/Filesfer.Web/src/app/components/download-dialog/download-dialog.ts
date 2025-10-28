import { Component, effect, inject, input, output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FileService } from '../../services/file.service';

interface DownloadStats {
  progress: number;
  downloadedBytes: number;
  totalBytes: number;
  speed: number;
  eta: string;
  errorMessage: string | null;
  downloading: boolean;
  startTime: number;
  lastUpdateTime: number;
  lastLoaded: number;
}

@Component({
  selector: 'app-download-dialog',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './download-dialog.html',
})
export class DownloadDialog {
  private readonly fileService = inject(FileService);

  filename = input.required<string>();
  closed = output<void>();

  stats = signal<DownloadStats>({
    progress: 0,
    downloadedBytes: 0,
    totalBytes: 0,
    speed: 0,
    eta: '—',
    errorMessage: null,
    downloading: true,
    startTime: 0,
    lastUpdateTime: 0,
    lastLoaded: 0
  });

  constructor() {
    effect(() => {
      const name = this.filename();
      if (name) this.startDownload(name);
    });
  }

  private resetStats(): void {
    const now = performance.now();
    this.stats.set({
      progress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      speed: 0,
      eta: '—',
      errorMessage: null,
      downloading: true,
      startTime: now,
      lastUpdateTime: now,
      lastLoaded: 0
    });
  }

  private async startDownload(filename: string): Promise<void> {
    this.resetStats();

    try {
      await this.fileService.downloadFile(filename, ({ loaded, total }) => {
        this.stats.update(s => {
          const now = performance.now();
          const elapsed = (now - s.lastUpdateTime) / 1000;
          let newSpeed = s.speed;
          let newEta = s.eta;

          if (elapsed > 0.5) {
            const diff = loaded - s.lastLoaded;
            newSpeed = diff / elapsed;
            const remaining = total - loaded;
            const estSeconds = newSpeed > 0 ? remaining / newSpeed : 0;
            newEta = this.formatTime(estSeconds);
            s.lastUpdateTime = now;
            s.lastLoaded = loaded;
          }

          return {
            ...s,
            downloadedBytes: loaded,
            totalBytes: total,
            progress: total ? Math.round((loaded / total) * 100) : 0,
            speed: newSpeed,
            eta: newEta
          };
        });
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown download error';
      this.stats.update(s => ({ ...s, errorMessage: message }));
    } finally {
      this.stats.update(s => ({ ...s, downloading: false }));
    }
  }

  private formatTime(seconds: number): string {
    if (!isFinite(seconds) || seconds <= 0) return '—';
    if (seconds < 60) return `${Math.round(seconds)}s`;
    if (seconds < 3600) return `${Math.floor(seconds / 60)}m ${Math.round(seconds % 60)}s`;
    return `${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  }

  formatBytes(bytes: number): string {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
  }

  close(): void {
    this.closed.emit();
  }
}
