using System.IO.Compression;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.AspNetCore.StaticFiles;
using Spectre.Console;

const string SHARED_FOLDER = "E:\\SharedFolder";
Directory.CreateDirectory(SHARED_FOLDER);


AnsiConsole.Write(
    new FigletText("Filesfer")
        .Centered()
        .Color(Color.Blue3));

AnsiConsole.MarkupLine("[bold yellow]Starting local file share API...[/]");

var builder = WebApplication.CreateBuilder(args);
builder.WebHost.ConfigureKestrel(options =>
{
  options.Limits.MaxRequestBodySize = null;
  options.Limits.MaxResponseBufferSize = null;
  options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(30);
  options.Limits.RequestHeadersTimeout = TimeSpan.FromMinutes(30);
  options.Limits.MinRequestBodyDataRate = 
        new MinDataRate(bytesPerSecond: 100, gracePeriod: TimeSpan.FromMinutes(30));
  options.Limits.MaxRequestBodySize = 10737418240;  //10GB
});

builder.Logging.ClearProviders();

builder.Logging.AddProvider(new SpectreLoggerProvider());
builder.Services.AddHealthChecks();
var app = builder.Build();

var provider = new FileExtensionContentTypeProvider();

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
  catch (DirectoryNotFoundException ex)
  {
    logger.LogError(ex, "Shared folder not found for {Operation}: {Folder}", operation, SHARED_FOLDER);
    context.Response.StatusCode = StatusCodes.Status404NotFound;
    await context.Response.WriteAsync($"Shared folder '{SHARED_FOLDER}' not found.");
  }
  catch (UnauthorizedAccessException ex)
  {
    logger.LogError(ex, "Access denied for {Operation} in folder: {Folder}", operation, SHARED_FOLDER);
    context.Response.StatusCode = StatusCodes.Status403Forbidden;
  }
  catch (OperationCanceledException)
  {
    logger.LogInformation("Request for {Operation} was canceled by the client.", operation);
    context.Response.StatusCode = StatusCodes.Status499ClientClosedRequest;
  }
  catch (Exception ex)
  {
    logger.LogError(ex, "Unexpected error during {Operation} in {Folder}", operation, SHARED_FOLDER);
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await context.Response.WriteAsync("Internal server error.");
  }
}



app.MapGet("/files", (HttpContext context, ILogger<Program> logger) =>
    SafeExecuteAsync(context, logger, async ctx =>
    {
      var files = Directory.GetFiles(SHARED_FOLDER)
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
      var path = Path.Combine(SHARED_FOLDER, safeFileName);

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
      var fullFolderPath = Path.Combine(SHARED_FOLDER, safeFolder);

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
      context.RequestAborted.ThrowIfCancellationRequested();
      var form = await ctx.Request.ReadFormAsync(context.RequestAborted);
      var file = form.Files["file"];

      if (file is null || file.Length == 0)
      {
        ctx.Response.StatusCode = StatusCodes.Status400BadRequest;
        await ctx.Response.WriteAsync("No file uploaded");
        return;
      }

      var safeFileName = Path.GetFileName(file.FileName);
      var filePath = Path.Combine(SHARED_FOLDER, safeFileName);

      await using var stream = File.Create(filePath);
      await file.CopyToAsync(stream);

      logger.LogInformation("/upload → {Filename} ({Size} KB)", safeFileName, file.Length / 1024);

      ctx.Response.ContentType = "application/json";
      await ctx.Response.WriteAsJsonAsync(new { file = safeFileName });
    }, "upload file")
);


app.MapHealthChecks("/health");

app.Run("http://0.0.0.0:5000");