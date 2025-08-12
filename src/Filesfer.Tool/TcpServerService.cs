using System.Net;
using System.Net.Sockets;
using System.Text;

namespace Filesfer.Tool;

public class TcpServerService : IDisposable
{
    private readonly List<TcpClient> _clients = [];
    private TcpListener? _listener;
    private CancellationTokenSource? _cts;
    private readonly string _sharedFolder;

    private readonly Dictionary<TcpClient, FileStream> _uploadStreams = [];

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
        _listener = new TcpListener(IPAddress.Any, port);
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

        lock (_clients)
        {
            foreach (var client in _clients)
            {
                client.Close();
            }
            _clients.Clear();
        }

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
                lock (_clients) _clients.Add(client);

                OnEvent?.Invoke($"Client connected: {client.Client.RemoteEndPoint}");
                _ = HandleClientAsync(client, token);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            OnEvent?.Invoke($"Error: {ex.Message}");
        }
    }

    private async Task HandleClientAsync(TcpClient client, CancellationToken token)
    {
        using var stream = client.GetStream();
        var buffer = new byte[8192];

        try
        {
            while (!token.IsCancellationRequested)
            {
                int bytesRead = await stream.ReadAsync(buffer, token);
                if (bytesRead == 0) break;

                string message = Encoding.UTF8.GetString(buffer, 0, bytesRead).Trim();

                if (message.StartsWith("UPLOAD_INIT|"))
                {
                    var fileName = message["UPLOAD_INIT|".Length..].Trim();
                    var safeFileName = Path.GetFileName(fileName);
                    var filePath = Path.Combine(_sharedFolder, safeFileName);

      
                    if (_uploadStreams.ContainsKey(client))
                    {
                        _uploadStreams[client].Dispose();
                        _uploadStreams.Remove(client);
                    }

                    var fs = new FileStream(filePath, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);
                    _uploadStreams[client] = fs;

                    await SendAsync(stream, "UPLOAD_ACK");
                    OnEvent?.Invoke($"Upload started: {safeFileName}");
                }
                else if (message.StartsWith("UPLOAD_CHUNK|"))
                {
                    if (!_uploadStreams.TryGetValue(client, out var fs))
                    {
                        await SendAsync(stream, "ERROR|Upload not initialized");
                        continue;
                    }

                    var base64Chunk = message["UPLOAD_CHUNK|".Length..];
                    var chunkBytes = Convert.FromBase64String(base64Chunk);
                    await fs.WriteAsync(chunkBytes, 0, chunkBytes.Length, token);
                    await SendAsync(stream, "UPLOAD_CHUNK_ACK");
                    OnEvent?.Invoke($"Received chunk ({chunkBytes.Length} bytes)");
                }
                else if (message == "UPLOAD_DONE")
                {
                    if (_uploadStreams.TryGetValue(client, out var fs))
                    {
                        await fs.FlushAsync(token);
                        fs.Dispose();
                        _uploadStreams.Remove(client);

                        await SendAsync(stream, "UPLOAD_COMPLETE");
                        OnEvent?.Invoke("Upload completed");
                    }
                    else
                    {
                        await SendAsync(stream, "ERROR|Upload not initialized");
                    }
                }
                else if (message.StartsWith("DOWNLOAD|"))
                {
                    var fileName = message["DOWNLOAD|".Length..].Trim();
                    var safeFileName = Path.GetFileName(fileName);
                    var filePath = Path.Combine(_sharedFolder, safeFileName);

                    if (!File.Exists(filePath))
                    {
                        await SendAsync(stream, "ERROR|File not found");
                        continue;
                    }

                    await SendAsync(stream, "DOWNLOAD_START");

                    using var fs = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 8192, true);
                    var readBuffer = new byte[8192];
                    int read;

                    while ((read = await fs.ReadAsync(readBuffer, token)) > 0)
                    {
                        var base64Chunk = Convert.ToBase64String(readBuffer, 0, read);
                        await SendAsync(stream, "DOWNLOAD_CHUNK|" + base64Chunk);
                    }

                    await SendAsync(stream, "DOWNLOAD_DONE");
                    OnEvent?.Invoke($"File sent: {safeFileName}");
                }
                else if (message == "LIST")
                {
                    var files = Directory.GetFiles(_sharedFolder).Select(Path.GetFileName);
                    var response = string.Join('|', files);
                    await SendAsync(stream, "LIST|" + response);
                    OnEvent?.Invoke("Sent file list");
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
            if (_uploadStreams.TryGetValue(client, out var fs))
            {
                fs.Dispose();
                _uploadStreams.Remove(client);
            }

            lock (_clients) _clients.Remove(client);
            client.Close();
            OnEvent?.Invoke($"Client disconnected: {client.Client.RemoteEndPoint}");
        }
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
