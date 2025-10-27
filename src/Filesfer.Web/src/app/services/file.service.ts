import { HttpClient, HttpErrorResponse } from "@angular/common/http";
import { inject, Injectable } from "@angular/core";
import { catchError, map, Observable, throwError } from "rxjs";

@Injectable({
  providedIn: 'root',
})
export class FileService {
  private httpClient = inject(HttpClient);
  private readonly BASE_ADDRESS = 'http://localhost:5000';

  public getFileList(): Observable<string[]> {
    return this.fetchDataAndHandleErrors<string[]>('files');
  }

  private fetchDataAndHandleErrors<T>(endpoint: string): Observable<T> {
    const requestUrl = `${this.BASE_ADDRESS}/${endpoint}`;

    return this.httpClient.get<{ data?: T } | T>(requestUrl, {
      observe: 'response'
    }).pipe(

      map(response => {
        const body = response.body;
        console.log('HTTP Response Body:', body);
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


