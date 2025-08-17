using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.StaticFiles;
using QRCoder;
using Spectre.Console;


var rule = new Rule("[yellow]Filesfer Tool[/]").RuleStyle("green").Centered();
AnsiConsole.Write(rule);
AnsiConsole.MarkupLine("[blue]Welcome to the Filesfer Server![/]");

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options =>
{
  options.Limits.MaxRequestBodySize = null;
  options.Limits.MaxResponseBufferSize = null;
  options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(30);
  options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(30);
  options.Limits.MinRequestBodyDataRate = null;
  options.Limits.MaxRequestBodySize = 10737418240;  //10GB

});

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
var app = builder.Build();

var sharedFolder = builder.Configuration["SharedFolderPath"];

if (string.IsNullOrWhiteSpace(sharedFolder))
{
  throw new InvalidOperationException("Shared folder path is not configured.");
}
else
{
  Directory.CreateDirectory(sharedFolder);
}

var port = 5000;
var ip = GetLocalIPAddress();
var url = $"http://{ip}:{port}";
var qrFile = Path.Combine(AppContext.BaseDirectory, "qrcode.png");

if (!File.Exists(qrFile))
{
  var qrGenerator = new QRCodeGenerator();
  var qrCodeData = qrGenerator.CreateQrCode(url, QRCodeGenerator.ECCLevel.Q);
  var qrCode = new PngByteQRCode(qrCodeData);
  var qrBytes = qrCode.GetGraphic(20);
  File.WriteAllBytes(qrFile, qrBytes);
}

AnsiConsole.MarkupLine($"\n[green]Server running at:[/] [blue]{url}[/]");
AnsiConsole.MarkupLine($"[yellow]QR Code saved at:[/] {qrFile}");
AnsiConsole.MarkupLine("[grey]Scan this QR with your phone to connect directly.[/]\n");

var openQr = AnsiConsole.Confirm("[cyan]Would you like to open the QR code image now?[/]");

if (openQr)
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
else
{
  AnsiConsole.MarkupLine("[grey]You can open the QR code manually later if needed.[/]");
}

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
  catch (DirectoryNotFoundException ex)
  {
    logger.LogError(ex, "Shared folder not found for {Operation}: {Folder}", operation, sharedFolder);
    context.Response.StatusCode = StatusCodes.Status404NotFound;
    await context.Response.WriteAsync($"Shared folder '{sharedFolder}' not found.");
  }
  catch (UnauthorizedAccessException ex)
  {
    logger.LogError(ex, "Access denied for {Operation} in folder: {Folder}", operation, sharedFolder);
    context.Response.StatusCode = StatusCodes.Status403Forbidden;
  }
  catch (OperationCanceledException)
  {
    logger.LogInformation("Request for {Operation} was canceled by the client.", operation);
    context.Response.StatusCode = StatusCodes.Status499ClientClosedRequest;
  }
  catch (Exception ex)
  {
    logger.LogError(ex, "Unexpected error during {Operation} in {Folder} {error}", operation, sharedFolder, ex.StackTrace);
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await context.Response.WriteAsync("Internal server error.");
  }
}



app.MapGet("/files", (HttpContext context, ILogger<Program> logger) =>
    SafeExecuteAsync(context, logger, async ctx =>
    {
      var files = Directory.GetFiles(sharedFolder)
          .Select(Path.GetFileName)
          .ToArray();

      ctx.Response.ContentType = "application/json";
      await ctx.Response.WriteAsJsonAsync(files);
    }, "list files")
);

app.MapGet("/download/{filename}", (HttpContext context, string filename, ILogger<Program> logger) =>
    SafeExecuteAsync(context, logger, async ctx =>
    {

      logger.LogInformation("Request to download file: {Filename}", filename);
      var safeFileName = Path.GetFileName(filename);
      var path = Path.Combine(sharedFolder, safeFileName);

      if (!File.Exists(path))
      {
        logger.LogWarning("404 File not found: {Filename}", safeFileName);
        ctx.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
      }

      if (!provider.TryGetContentType(path, out var contentType))
        contentType = "application/octet-stream";

      var fileInfo = new FileInfo(path);
      logger.LogInformation("/download/{Filename} → {Size} KB", safeFileName, fileInfo.Length / 1024);

      ctx.Response.ContentType = contentType;
      ctx.Response.Headers.ContentDisposition = $"attachment; filename=\"{safeFileName}\"";
      ctx.Response.ContentLength = fileInfo.Length;

      await ctx.Response.SendFileAsync(path, ctx.RequestAborted);
    }, "download file")
);

app.MapGet("/download-folder/{folder}", (HttpContext context, string folder, ILogger<Program> logger) =>
    SafeExecuteAsync(context, logger, async ctx =>
    {
      var safeFolder = Path.GetFileName(folder);
      var fullFolderPath = Path.Combine(sharedFolder, safeFolder);

      if (!Directory.Exists(fullFolderPath))
      {
        logger.LogWarning("404 Folder not found: {Folder}", safeFolder);
        ctx.Response.StatusCode = StatusCodes.Status404NotFound;
        return;
      }

      var tempZipPath = Path.Combine(Path.GetTempPath(), $"{safeFolder}_{Guid.NewGuid()}.zip");
      ZipFile.CreateFromDirectory(fullFolderPath, tempZipPath);

      logger.LogInformation("/download-folder/{Folder} → Sending zip", safeFolder);

      ctx.Response.ContentType = "application/zip";
      ctx.Response.Headers.ContentDisposition = $"attachment; filename=\"{safeFolder}.zip\"";
      await using var zipStream = File.OpenRead(tempZipPath);
      await zipStream.CopyToAsync(ctx.Response.Body, 81920, ctx.RequestAborted);

      File.Delete(tempZipPath);
    }, "download folder")
);

app.MapPost("/upload", (HttpContext context, ILogger<Program> logger) =>
  SafeExecuteAsync(context, logger, async ctx =>
  {
    var form = await ctx.Request.ReadFormAsync(context.RequestAborted);
    var file = form.Files["file"];

    if (file is null || file.Length == 0)
    {
      ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
      await ctx.Response.WriteAsync("No file uploaded");
      return;
    }

    var safeFileName = Path.GetFileName(file.FileName);
    var filePath = Path.Combine(sharedFolder, safeFileName);

    await using var fileStream = file.OpenReadStream();
    await using var localStream = File.Create(filePath);

    await fileStream.CopyToAsync(localStream, ctx.RequestAborted);

    logger.LogInformation("/upload → {Filename} ({Size} KB)", safeFileName, file.Length / 1024);

    ctx.Response.ContentType = "application/json";
    await ctx.Response.WriteAsJsonAsync(new { file = safeFileName });
  }, "upload file")
);


app.MapHealthChecks("/health");

app.Run("http://0.0.0.0:5000");

static string GetLocalIPAddress()
{
  var host = Dns.GetHostEntry(Dns.GetHostName());
  foreach (var ip in host.AddressList)
  {
    if (ip.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
      return ip.ToString();
  }
  return "127.0.0.1";
}