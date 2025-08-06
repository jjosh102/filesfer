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

app.MapGet("/files", (ILogger<Program> logger) =>
{
  var files = Directory.GetFiles(SHARED_FOLDER);
  var fileNames = files.Select(f => Path.GetFileName(f)).ToArray();

  logger.LogInformation("/files → {Count} file(s)", fileNames.Length);
  return fileNames;
});

app.MapGet("/download/{filename}", (string filename, ILogger<Program> logger) =>
{
  var path = Path.Combine(SHARED_FOLDER, filename);

  if (!File.Exists(path))
  {
    logger.LogWarning("404 File not found: {Filename}", filename);
    return Results.NotFound();
  }

  var sizeKb = new FileInfo(path).Length / 1024;
  logger.LogInformation("/download/{Filename} → {Size} KB", filename, sizeKb);
  return Results.File(path);
});

app.Run("http://0.0.0.0:5000");