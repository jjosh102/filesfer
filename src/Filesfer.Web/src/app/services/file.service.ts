import { HttpClient, HttpErrorResponse } from "@angular/common/http";
import { inject, Injectable } from "@angular/core";
import { catchError, map, Observable, throwError } from "rxjs";

@Injectable({
  providedIn: 'root',
})
export class FileService {
  private readonly BASE_ADDRESS = `${window.location.protocol}//${window.location.hostname}:${5000}`;
  private httpClient = inject(HttpClient);

  public getFileList(): Observable<string[]> {
    return this.fetchDataAndHandleErrors<string[]>('files');
  }

  public async downloadFile(
    filename: string,
    onProgress: (data: { loaded: number; total: number }) => void
  ): Promise<void> {
    const url = `${this.BASE_ADDRESS}/download/${encodeURIComponent(filename)}`;
    const response = await fetch(url);

    if (!response.ok) throw new Error(`Download failed: ${response.statusText}`);

    const total = Number(response.headers.get('Content-Length')) || 0;
    const reader = response.body!.getReader();
    const chunks: BlobPart[] = [];
    let loaded = 0;

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) {
        chunks.push(value);
        loaded += value.length;
        onProgress({ loaded, total });
      }
    }

    const blob = new Blob(chunks, { type: 'application/octet-stream' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  private fetchDataAndHandleErrors<T>(endpoint: string): Observable<T> {
    const requestUrl = `${this.BASE_ADDRESS}/${endpoint}`;

    return this.httpClient.get<{ data?: T } | T>(requestUrl, {
      observe: 'response'
    }).pipe(

      map(response => {
        const body = response.body;
        const data: T =
          (body as { data?: T })?.data !== undefined
            ? (body as { data?: T }).data as T
            : body as T;

        if (data === undefined || data === null) {
          throw new Error('Empty or invalid response body');
        }
        return data;
      }),

      catchError((error: HttpErrorResponse): Observable<T> => {
        console.error('HTTP Error:', error);
        return throwError(() => new Error(`HTTP Error: ${error.status} - ${error.message}`));
      })
    );
  }
}


