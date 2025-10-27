import { Component, DestroyRef, inject, OnInit, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { FileService } from './services/file.service';

@Component({
  selector: 'app-root',
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements OnInit {
  protected readonly title = signal('Filesfer.Web');
  private fileService = inject(FileService);
  private destroyRef = inject(DestroyRef);
  files = signal<string[]>([]);

  ngOnInit() {
    const subscription = this.fileService.getFileList()
      .subscribe({
        next: (result) => {
          if (result) {
            this.files.set(result);
          }
        }
      },);

    this.destroyRef.onDestroy(() => {
      subscription.unsubscribe();
    });
  }
}
