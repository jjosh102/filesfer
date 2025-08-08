using System.IO.Compression;
using Microsoft.AspNetCore.StaticFiles;
using Spectre.Console;

const string SHARED_FOLDER = "E:\\SharedFolder";
Directory.CreateDirectory(SHARED_FOLDER);


AnsiConsole.Write(
    new FigletText("Filesfer")
        .Centered()
        .Color(Color.Green));

AnsiConsole.MarkupLine("[bold yellow]Starting local file share API...[/]");

var builder = WebApplication.CreateBuilder(args);

builder.Logging.ClearProviders();

builder.Logging.AddProvider(new SpectreLoggerProvider());

builder.Logging.SetMinimumLevel(LogLevel.Information);
var app = builder.Build();

var provider = new FileExtensionContentTypeProvider();

app.MapGet("/files", (ILogger<Program> logger) =>
{
  var files = Directory.GetFiles(SHARED_FOLDER);
  var fileNames = files.Select(Path.GetFileName).ToArray();

  logger.LogInformation("/files → {Count} file(s)", fileNames.Length);
  return fileNames;
});

app.MapGet("/download/{filename}", (string filename, ILogger<Program> logger) =>
{
  var safeFileName = Path.GetFileName(filename);
  var path = Path.Combine(SHARED_FOLDER, safeFileName);

  if (!File.Exists(path))
  {
    logger.LogWarning("404 File not found: {Filename}", safeFileName);
    return Results.NotFound();
  }

  provider.TryGetContentType(path, out var contentType);
  contentType ??= "application/octet-stream";

  var sizeKb = new FileInfo(path).Length / 1024;
  logger.LogInformation("/download/{Filename} → {Size} KB", safeFileName, sizeKb);

  return Results.File(path, contentType, fileDownloadName: safeFileName);
});

// For streaming
// app.MapGet("/download/{filename}", async (HttpContext context, string filename, ILogger<Program> logger) =>
// {
//   var safeFileName = Path.GetFileName(filename);
//   var path = Path.Combine(SHARED_FOLDER, safeFileName);

//   if (!File.Exists(path))
//   {
//     logger.LogWarning("404 File not found: {Filename}", safeFileName);
//     return Results.NotFound();
//   }

//   provider.TryGetContentType(path, out var contentType);


//   context.Response.ContentType = contentType ??= "application/octet-stream";
//   context.Response.Headers.Append("Content-Disposition", $"attachment; filename=\"{safeFileName}\"");

//   await using var stream = File.OpenRead(path);
//   await stream.CopyToAsync(context.Response.Body);
//   return Results.Ok();

// });

app.MapGet("/download-folder/{folder}", (string folder, ILogger<Program> logger) =>
{
  var safeFolder = Path.GetFileName(folder);
  var fullFolderPath = Path.Combine(SHARED_FOLDER, safeFolder);

  if (!Directory.Exists(fullFolderPath))
  {
    logger.LogWarning("404 Folder not found: {Folder}", safeFolder);
    return Results.NotFound();
  }

  var tempZipPath = Path.Combine(Path.GetTempPath(), $"{safeFolder}_{Guid.NewGuid()}.zip");

  ZipFile.CreateFromDirectory(fullFolderPath, tempZipPath);

  logger.LogInformation("/download-folder/{Folder} → Sending zip", safeFolder);
  return Results.File(tempZipPath, "application/zip", $"{safeFolder}.zip");
});

app.MapPost("/upload", async (HttpRequest request, ILogger<Program> logger) =>
{
  try
  {
    
    var form = await request.ReadFormAsync();
    var file = form.Files["file"];

    if (file is null || file.Length == 0)
      return Results.BadRequest("No file uploaded");

    var safeFileName = Path.GetFileName(file.FileName);
    var filePath = Path.Combine("E:\\SharedFolder", safeFileName);

    using var stream = File.Create(filePath);
    await file.CopyToAsync(stream);

    logger.LogInformation("/upload → {Filename} ({Size} KB)", safeFileName, file.Length / 1024);
    return Results.Ok(new { file = safeFileName });
  }
  catch (Exception ex)
  {
    logger.LogError(ex, "Upload failed");
    return Results.BadRequest("Exception: " + ex.Message);
  }
});

app.Run("http://0.0.0.0:5000");