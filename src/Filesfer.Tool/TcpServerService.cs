using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Filesfer.Tool;

public class TcpServerService : IDisposable
{
    private static readonly ConcurrentDictionary<TcpClient, bool> _clients = [];
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private readonly string _sharedFolder;

    private static readonly ConcurrentDictionary<TcpClient, FileStream> _uploadStreams = [];

    public bool IsRunning { get; private set; }
    public event Action<string>? OnEvent;

    public TcpServerService(string sharedFolder)
    {
        _sharedFolder = sharedFolder;
        Directory.CreateDirectory(_sharedFolder);
    }

    public void Start(int port)
    {
        if (IsRunning) return;

        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, 9000);
        _listener.Start();
        IsRunning = true;

        OnEvent?.Invoke($"Server started on port {port}");
        _ = AcceptClientsAsync(_cts.Token);
    }

    public void Stop()
    {
        if (!IsRunning) return;

        _cts?.Cancel();
        _listener?.Stop();

        foreach (var client in _clients.Keys)
        {
            client.Close();
        }
        _clients.Clear();

        foreach (var fs in _uploadStreams.Values)
            fs.Dispose();


        _uploadStreams.Clear();

        IsRunning = false;
        OnEvent?.Invoke("Server stopped");
    }

    private async Task AcceptClientsAsync(CancellationToken token)
    {
        try
        {
            while (!token.IsCancellationRequested)
            {
                var client = await _listener!.AcceptTcpClientAsync(token);
                _clients.TryAdd(client, true);

                OnEvent?.Invoke($"Client connected: {client.Client.RemoteEndPoint}");
                _ = HandleClientAsync(client, token);
            }
        }
        catch (OperationCanceledException ex)
        {
            OnEvent?.Invoke($"Error: {ex.Message}");
        }
        catch (Exception ex)
        {
            OnEvent?.Invoke($"Error: {ex.Message}");
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken token)
    {
        using var stream = client.GetStream();
        using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);

        try
        {
            while (!token.IsCancellationRequested)
            {
                string? message = await reader.ReadLineAsync(token);
                if (message is null) break;

                if (message.StartsWith("UPLOAD_INIT|"))
                {
                    var parts = message.Split('|');
                    if (parts.Length != 3)
                    {
                        await SendAsync(stream, "ERROR|Invalid UPLOAD_INIT command format");
                        continue;
                    }

                    var fileName = parts[1];
                    var totalBytesToRead = long.Parse(parts[2]);
                    await HandleUploadAsync(client, stream, fileName, totalBytesToRead, token);
                }
                else if (message.StartsWith("DOWNLOAD|"))
                {
                    var fileName = message["DOWNLOAD|".Length..].Trim();
                    await HandleDownloadAsync(stream, fileName, token);
                }
                else if (message == "LIST")
                {
                    await HandleListAsync(stream);
                }
                else
                {
                    await SendAsync(stream, "ERROR|Unknown command");
                    OnEvent?.Invoke($"Unknown command: {message}");
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            OnEvent?.Invoke($"Client error: {ex.Message}");
        }
        finally
        {
            if (_uploadStreams.TryRemove(client, out var fileStream))
            {
                fileStream.Dispose();
            }

            _clients.TryRemove(client, out _);
            client.Close();
            OnEvent?.Invoke($"Client disconnected: {client.Client.RemoteEndPoint}");
        }
    }

    private async Task HandleUploadAsync(
     TcpClient client,
     NetworkStream stream,
     string fileName,
     long totalBytes,
     CancellationToken token)
    {
        var safeFileName = Path.GetFileName(fileName);
        var filePath = Path.Combine(_sharedFolder, safeFileName);

        try
        {
            await SendAsync(stream, "UPLOAD_ACK");
            OnEvent?.Invoke($"Upload started: {safeFileName}, expecting {totalBytes} bytes");

            using var fs = new FileStream(
                filePath,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                bufferSize: 8192,
                useAsync: true);

            _uploadStreams[client] = fs;

            var buffer = new byte[8192];
            long bytesReadTotal = 0;

            while (bytesReadTotal < totalBytes && !token.IsCancellationRequested)
            {
                int toRead = (int)Math.Min(buffer.Length, totalBytes - bytesReadTotal);
                int read = await stream.ReadAsync(buffer.AsMemory(0, toRead), token);

                if (read == 0) break;

                await fs.WriteAsync(buffer.AsMemory(0, read), token);
                bytesReadTotal += read;
            }

            _uploadStreams.TryRemove(client, out _);

            if (bytesReadTotal == totalBytes && !token.IsCancellationRequested)
            {
                await fs.FlushAsync(token);
                await SendAsync(stream, "UPLOAD_COMPLETE");
                OnEvent?.Invoke("Upload completed successfully");
            }
            else
            {
                fs.Close();
                File.Delete(filePath);
                await SendAsync(stream, "ERROR|Upload incomplete or canceled");
                OnEvent?.Invoke("Upload failed (incomplete or canceled)");
            }
        }
        catch (OperationCanceledException)
        {
            File.Delete(filePath);
            _uploadStreams.TryRemove(client, out _);
            await SendAsync(stream, "ERROR|Upload canceled");
            OnEvent?.Invoke("Upload canceled");
        }
        catch (Exception ex)
        {
            File.Delete(filePath);
            _uploadStreams.TryRemove(client, out _);
            await SendAsync(stream, $"ERROR|Upload failed: {ex.Message}");
            OnEvent?.Invoke($"Upload error: {ex.Message}");
        }
    }

    private async Task HandleDownloadAsync(NetworkStream stream, string fileName, CancellationToken token)
    {
        var safeFileName = Path.GetFileName(fileName);
        var filePath = Path.Combine(_sharedFolder, safeFileName);

        if (!File.Exists(filePath))
        {
            await SendAsync(stream, "ERROR|File not found");
            return;
        }

        try
        {
            var fileInfo = new FileInfo(filePath);
            await SendAsync(stream, $"DOWNLOAD_START|{fileInfo.Length}");

            using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 8192, true);
            var buffer = new byte[8192];
            int bytesRead;

            while ((bytesRead = await fs.ReadAsync(buffer.AsMemory(0, buffer.Length), token)) > 0)
            {
                await stream.WriteAsync(buffer.AsMemory(0, bytesRead), token);
                OnEvent?.Invoke($"Sent chunk ({bytesRead} bytes) of {safeFileName}");
            }

            await SendAsync(stream, "DOWNLOAD_DONE");
            OnEvent?.Invoke($"File sent: {safeFileName}");
        }
        catch (Exception ex)
        {
            await SendAsync(stream, $"ERROR|Download failed: {ex.Message}");
            OnEvent?.Invoke($"Download error: {ex.Message}");
        }
    }
    private async Task HandleListAsync(NetworkStream stream)
    {
        var files = Directory.GetFiles(_sharedFolder).Select(Path.GetFileName);
        var response = string.Join('|', files);
        await SendAsync(stream, "LIST|" + response);
        OnEvent?.Invoke("Sent file list");
    }
    private static async Task SendAsync(NetworkStream stream, string message)
    {
        var msgBytes = Encoding.UTF8.GetBytes(message + "\n");
        await stream.WriteAsync(msgBytes);
    }

    public void Dispose()
    {
        Stop();
        _cts?.Dispose();
    }
}
