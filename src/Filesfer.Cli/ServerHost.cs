using System.Net;
using System.Net.Sockets;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.StaticFiles;

namespace Filesfer.Cli;

public interface IServerHost
{
  bool IsRunning { get; }
  string? Url { get; }
  string CurrentStoragePath { get; }

  Task StartAsync(CancellationToken token = default);
  Task StopAsync();
}

public class ServerHost : IServerHost
{
  private WebApplication? _app;
  private Task? _serverTask;
  private CancellationTokenSource? _cts;

  public bool IsRunning { get; private set; }
  public string? Url { get; private set; }
  public string CurrentStoragePath { get; private set; } = string.Empty;

  private readonly int _port;
  private readonly string _defaultFolder;

  public ServerHost(int port = 5000, string? folder = null)
  {
    _port = port;
    _defaultFolder = folder ??
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
  }

  public async Task StartAsync(CancellationToken token = default)
  {
    if (IsRunning)
      return;

    if (IsPortInUse(_port))
      throw new InvalidOperationException($"Port {_port} is already in use.");

    _cts = CancellationTokenSource.CreateLinkedTokenSource(token);

    var builder = WebApplication.CreateBuilder();
    builder.WebHost.ConfigureKestrel(options =>
    {
      options.Limits.MaxRequestBodySize = 10L * 1024 * 1024 * 1024; // 10GB
      options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(30);
      options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(30);
      options.ListenAnyIP(_port);
    });

    builder.Services.Configure<FormOptions>(options =>
    {
      options.MultipartBodyLengthLimit = 10L * 1024 * 1024 * 1024; // 10 GB
    });


    builder.Logging.ClearProviders();
    builder.Logging.AddProvider(new SpectreLoggerProvider());
    builder.Services.AddHealthChecks();

    _app = builder.Build();

    CurrentStoragePath = _defaultFolder;
    Directory.CreateDirectory(CurrentStoragePath);

    var provider = new FileExtensionContentTypeProvider();

    async Task SafeExecuteAsync(
       HttpContext context,
       ILogger logger,
       Func<HttpContext, Task> action,
       string operation)
    {
      try
      {
        await action(context);
      }
      catch (Exception ex) when (ex is DirectoryNotFoundException ||
                                 ex is UnauthorizedAccessException ||
                                 ex is OperationCanceledException)
      {
        context.Response.StatusCode = ex switch
        {
          DirectoryNotFoundException => StatusCodes.Status404NotFound,
          UnauthorizedAccessException => StatusCodes.Status403Forbidden,
          OperationCanceledException => StatusCodes.Status499ClientClosedRequest,
          _ => StatusCodes.Status500InternalServerError
        };
        logger.LogError(ex, "Error in {Operation} with folder {Folder}", operation, CurrentStoragePath);
      }
      catch (Exception ex)
      {
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        logger.LogError(ex, "Unexpected error in {Operation}: {Message}", operation, ex.Message);
      }
    }


    _app.MapGet("/files", (HttpContext ctx, ILogger<ServerHost> logger) =>
        SafeExecuteAsync(ctx, logger, async context =>
        {
          var files = Directory.GetFiles(CurrentStoragePath)
                  .Select(Path.GetFileName)
                  .ToArray();

          context.Response.ContentType = "application/json";
          await context.Response.WriteAsJsonAsync(files);
        }, "list files"));

    _app.MapGet("/download/{filename}", (HttpContext ctx, string filename, ILogger<ServerHost> logger) =>
        SafeExecuteAsync(ctx, logger, async context =>
        {
          var safeFileName = Path.GetFileName(filename);
          var path = Path.Combine(CurrentStoragePath, safeFileName);

          if (!File.Exists(path))
          {
            context.Response.StatusCode = StatusCodes.Status404NotFound;
            return;
          }

          if (!provider.TryGetContentType(path, out var contentType))
            contentType = "application/octet-stream";

          var fileInfo = new FileInfo(path);
          context.Response.ContentType = contentType;
          context.Response.Headers.ContentDisposition = $"attachment; filename=\"{safeFileName}\"";
          context.Response.ContentLength = fileInfo.Length;

          await context.Response.SendFileAsync(path, context.RequestAborted);
        }, "download file"));

    _app.MapPost("/upload", (HttpContext ctx, ILogger<ServerHost> logger) =>
        SafeExecuteAsync(ctx, logger, async context =>
        {
          var form = await context.Request.ReadFormAsync(context.RequestAborted);
          var file = form.Files["file"];
          if (file == null || file.Length == 0)
          {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("No file uploaded");
            return;
          }

          var safeFileName = Path.GetFileName(file.FileName);
          var filePath = Path.Combine(CurrentStoragePath, safeFileName);

          await using var fileStream = file.OpenReadStream();
          await using var localStream = File.Create(filePath);

          await fileStream.CopyToAsync(localStream, context.RequestAborted);

          context.Response.ContentType = "application/json";
          await context.Response.WriteAsJsonAsync(new { file = safeFileName });
        }, "upload file"));

    _app.MapHealthChecks("/health");


    _serverTask = _app.RunAsync(_cts.Token);
    Url = $"http://localhost:{_port}";
    IsRunning = true;

    await Task.Delay(200, token);
  }

  public async Task StopAsync()
  {
    if (!IsRunning || _app is null || _cts is null)
      return;

    _cts.Cancel();

    try
    {
      await _serverTask!;
    }
    catch (OperationCanceledException) { }

    IsRunning = false;
    Url = null;
  }

  private static bool IsPortInUse(int port)
  {
    try
    {
      using var client = new TcpClient();
      var task = client.ConnectAsync(IPAddress.Loopback, port);
      var done = task.Wait(TimeSpan.FromMilliseconds(200));
      return done && client.Connected;
    }
    catch { return false; }
  }
}
