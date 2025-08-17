using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.StaticFiles;
using QRCoder;
using Spectre.Console;

var app = BuildApp(args);
ConfigureEndpoints(app);
RunApp(app);


static WebApplication BuildApp(string[] args)
{
  var port = 5000;
  var ip = GetLocalIPAddress();
  var url = $"http://{ip}:{port}";

  ShowBanner();
  GenerateQrCode(url);

  var builder = WebApplication.CreateBuilder(args);

  ConfigureKestrel(builder, port);
  ConfigureServices(builder);

  var app = builder.Build();

  ValidateSharedFolder(builder);

  return app;
}


static void ConfigureEndpoints(WebApplication app)
{
  var sharedFolder = app.Configuration["SharedFolderPath"];
  var provider = new FileExtensionContentTypeProvider();

  app.MapGet("/files", (HttpContext ctx, ILogger<Program> logger) =>
      SafeExecuteAsync(ctx, logger, async c =>
      {
        var files = Directory.GetFiles(sharedFolder!)
              .Select(Path.GetFileName)
              .ToArray();

        c.Response.ContentType = "application/json";
        await c.Response.WriteAsJsonAsync(files);
      }, "list files"));

  app.MapGet("/download/{filename}", (HttpContext ctx, string filename, ILogger<Program> logger) =>
      SafeExecuteAsync(ctx, logger, async c =>
      {
        var safeFileName = Path.GetFileName(filename);
        var path = Path.Combine(sharedFolder!, safeFileName);

        if (!File.Exists(path))
        {
          c.Response.StatusCode = StatusCodes.Status404NotFound;
          return;
        }

        if (!provider.TryGetContentType(path, out var contentType))
          contentType = "application/octet-stream";

        var fileInfo = new FileInfo(path);
        c.Response.ContentType = contentType;
        c.Response.Headers.ContentDisposition = $"attachment; filename=\"{safeFileName}\"";
        c.Response.ContentLength = fileInfo.Length;

        await c.Response.SendFileAsync(path, c.RequestAborted);
      }, "download file"));

  app.MapGet("/download-folder/{folder}", (HttpContext ctx, string folder, ILogger<Program> logger) =>
      SafeExecuteAsync(ctx, logger, async c =>
      {
        var safeFolder = Path.GetFileName(folder);
        var fullFolderPath = Path.Combine(sharedFolder!, safeFolder);

        if (!Directory.Exists(fullFolderPath))
        {
          c.Response.StatusCode = StatusCodes.Status404NotFound;
          return;
        }

        var tempZipPath = Path.Combine(Path.GetTempPath(), $"{safeFolder}_{Guid.NewGuid()}.zip");
        ZipFile.CreateFromDirectory(fullFolderPath, tempZipPath);

        c.Response.ContentType = "application/zip";
        c.Response.Headers.ContentDisposition = $"attachment; filename=\"{safeFolder}.zip\"";

        await using var zipStream = File.OpenRead(tempZipPath);
        await zipStream.CopyToAsync(c.Response.Body, 81920, c.RequestAborted);

        File.Delete(tempZipPath);
      }, "download folder"));

  app.MapPost("/upload", (HttpContext ctx, ILogger<Program> logger) =>
      SafeExecuteAsync(ctx, logger, async c =>
      {
        var form = await c.Request.ReadFormAsync(c.RequestAborted);
        var file = form.Files["file"];

        if (file is null || file.Length == 0)
        {
          c.Response.StatusCode = StatusCodes.Status400BadRequest;
          await c.Response.WriteAsync("No file uploaded");
          return;
        }

        var safeFileName = Path.GetFileName(file.FileName);
        var filePath = Path.Combine(sharedFolder!, safeFileName);

        await using var fileStream = file.OpenReadStream();
        await using var localStream = File.Create(filePath);

        await fileStream.CopyToAsync(localStream, c.RequestAborted);

        c.Response.ContentType = "application/json";
        await c.Response.WriteAsJsonAsync(new { file = safeFileName });
      }, "upload file"));

  app.MapHealthChecks("/health");
}


static void RunApp(WebApplication app)
{
  var port = 5000;
  var ip = GetLocalIPAddress();
  var url = $"http://{ip}:{port}";
  var qrFile = Path.Combine(AppContext.BaseDirectory, "qrcode.png");

  AnsiConsole.MarkupLine($"\n[green]Server running at:[/] [blue]{url}[/]");
  AnsiConsole.MarkupLine($"[yellow]QR Code saved at:[/] {qrFile}");
  AnsiConsole.MarkupLine("[grey]Scan this QR with your phone to connect directly.[/]\n");

  if (AnsiConsole.Confirm("[cyan]Would you like to open the QR code image now?[/]"))
    OpenQrCode(qrFile);
  else
    AnsiConsole.MarkupLine("[grey]You can open the QR code manually later if needed.[/]");

  app.Run();
}


static void ConfigureKestrel(WebApplicationBuilder builder, int port)
{
  builder.WebHost.ConfigureKestrel(options =>
  {
    options.Limits.MaxRequestBodySize = 10737418240; // 10GB
    options.Limits.MaxResponseBufferSize = null;
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(30);
    options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(30);
    options.Limits.MinRequestBodyDataRate = null;
    options.Listen(IPAddress.Any, port);
  });
}


static void ConfigureServices(WebApplicationBuilder builder)
{
  builder.Services.Configure<FormOptions>(options =>
  {
    options.MultipartBodyLengthLimit = 10737418240; // 10 GB
  });

  builder.Configuration
      .AddUserSecrets<Program>()
      .AddEnvironmentVariables();

  builder.Logging.ClearProviders();
  builder.Logging.AddProvider(new SpectreLoggerProvider());

  builder.Services.AddHealthChecks();
}


static void ValidateSharedFolder(WebApplicationBuilder builder)
{
  var sharedFolder = builder.Configuration["SharedFolderPath"];

  if (string.IsNullOrWhiteSpace(sharedFolder))
    throw new InvalidOperationException("Shared folder path is not configured.");

  Directory.CreateDirectory(sharedFolder);
}


static async Task SafeExecuteAsync(
    HttpContext context,
    ILogger logger,
    Func<HttpContext, Task> action,
    string operation)
{
  try
  {
    await action(context);
  }
  catch (DirectoryNotFoundException)
  {
    context.Response.StatusCode = StatusCodes.Status404NotFound;
    await context.Response.WriteAsync("Shared folder not found.");
  }
  catch (UnauthorizedAccessException)
  {
    context.Response.StatusCode = StatusCodes.Status403Forbidden;
  }
  catch (OperationCanceledException)
  {
    context.Response.StatusCode = StatusCodes.Status499ClientClosedRequest;
  }
  catch
  {
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await context.Response.WriteAsync("Internal server error.");
  }
}


static void GenerateQrCode(string url)
{
  var qrFile = Path.Combine(AppContext.BaseDirectory, "qrcode.png");

  if (File.Exists(qrFile))
    return;

  var qrGenerator = new QRCodeGenerator();
  var qrCodeData = qrGenerator.CreateQrCode(url, QRCodeGenerator.ECCLevel.Q);
  var qrCode = new PngByteQRCode(qrCodeData);
  var qrBytes = qrCode.GetGraphic(20);

  File.WriteAllBytes(qrFile, qrBytes);
}


static void ShowBanner()
{
  var rule = new Rule("[yellow]Filesfer Server[/]").RuleStyle("green").Centered();
  AnsiConsole.Write(rule);
  AnsiConsole.MarkupLine("[blue]Welcome to the Filesfer Server![/]");
}


static void OpenQrCode(string qrFile)
{
  try
  {
    if (OperatingSystem.IsWindows())
      Process.Start(new ProcessStartInfo(qrFile) { UseShellExecute = true });
    else if (OperatingSystem.IsMacOS())
      Process.Start("open", qrFile);
    else if (OperatingSystem.IsLinux())
      Process.Start("xdg-open", qrFile);

    AnsiConsole.MarkupLine("[green]QR code image opened successfully![/]");
  }
  catch (Exception ex)
  {
    AnsiConsole.MarkupLine($"[red]Failed to open QR code:[/] {ex.Message}");
  }
}


static string GetLocalIPAddress()
{
  var host = Dns.GetHostEntry(Dns.GetHostName());
  foreach (var ip in host.AddressList)
    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
      return ip.ToString();

  return "127.0.0.1";
}
