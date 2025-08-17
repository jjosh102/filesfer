using Filesfer.Cli;
using Spectre.Console;

namespace Filesfer.Cli;

public static class Program
{
  public static async Task Main(string[] args)
  {
    AnsiConsole.Write(new FigletText("Filesfer").Centered().Color(Color.Purple));

    var services = new ServiceCollection();
    services.AddSingleton<IAppConfig, AppConfig>();
    services.AddSingleton<IServerHost, ServerHost>();
    using var provider = services.BuildServiceProvider();

    var config = provider.GetRequiredService<IAppConfig>();
    config.Load();

    var server = provider.GetRequiredService<IServerHost>();

    Console.CancelKeyPress += async (_, e) =>
    {
      e.Cancel = true;
      await server.StopAsync();
      Environment.Exit(0);
    };

    while (true)
    {
      AnsiConsole.Write(new Rule().RuleStyle("grey"));
      var grid = new Grid().AddColumn().AddColumn();
      grid.AddRow("[bold]Server:[/]", server.IsRunning ? "[green]Running[/]" : "[red]Stopped[/]");
      grid.AddRow("[bold]URL:[/]", server.Url is null ? "-" : $"[blue]{server.Url}[/]");
      grid.AddRow("[bold]Storage:[/]", $"[yellow]{config.StoragePath}[/]");
      grid.AddRow("[bold]Port:[/]", $"[cyan]{config.Port}[/]");
      AnsiConsole.Write(grid);

      var choice = AnsiConsole.Prompt(
          new SelectionPrompt<string>()
              .Title("\nSelect an action")
              .AddChoices(new[]
              {
                        server.IsRunning ? "Stop Server" : "Start Server",
                        "List Files",
                        "Set Storage Folder",
                        "Set Port",
                        "Show Logs",
                        "Exit"
              }));

      try
      {
        switch (choice)
        {
          case "Start Server":
            await server.StartAsync();
            break;

          case "Stop Server":
            await server.StopAsync();
            break;

          case "List Files":
            {
              EnsureFolderValid(config, server);
              var files = Directory.GetFiles(server.CurrentStoragePath)
                                   .OrderBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase)
                                   .ToArray();
              var table = new Table().Border(TableBorder.Rounded)
                                     .AddColumn("[bold]File[/]")
                                     .AddColumn("[bold]Size[/]")
                                     .AddColumn("[bold]Modified[/]");
              foreach (var f in files)
              {
                var fi = new FileInfo(f);
                table.AddRow(Path.GetFileName(f),
                             $"{fi.Length:n0} bytes",
                             fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm"));
              }
              if (files.Length == 0) AnsiConsole.MarkupLine("[grey]No files found.[/]");
              else AnsiConsole.Write(table);
              Pause();
              break;
            }

          case "Set Storage Folder":
            {
              var input = AnsiConsole.Ask<string>("Enter full folder path:");
              if (!TryValidateFolder(input, out var reason))
              {
                AnsiConsole.MarkupLine($"[red]Invalid path:[/] {reason}");
                Pause();
                break;
              }

              try
              {
                Directory.CreateDirectory(input);
                var test = Path.Combine(input, ".filesfer_write_test");
                File.WriteAllText(test, "ok");
                File.Delete(test);

                config.StoragePath = input;
                config.Save();

                AnsiConsole.MarkupLine($"[green]Storage folder set to[/] [yellow]{input}[/]");

                if (server.IsRunning)
                {
                  AnsiConsole.MarkupLine("[grey]Restarting server to apply changes...[/]");
                  await server.StopAsync();
                  await server.StartAsync();
                }
              }
              catch (Exception ex)
              {
                AnsiConsole.MarkupLine($"[red]Failed to set folder:[/] {ex.Message}");
              }

              Pause();
              break;
            }

          case "Set Port":
            {
              var port = AnsiConsole.Ask<int>("Enter port (1-65535):");
              if (port is < 1 or > 65535)
              {
                AnsiConsole.MarkupLine("[red]Invalid port.[/]");
                Pause();
                break;
              }

              config.Port = port;
              config.Save();
              AnsiConsole.MarkupLine($"[green]Port set to {port}[/]");

              if (server.IsRunning)
              {
                AnsiConsole.MarkupLine("[grey]Restarting server to apply changes...[/]");
                await server.StopAsync();
                await server.StartAsync();
              }

              Pause();
              break;
            }


          case "Exit":
            await server.StopAsync();
            return;
        }
      }
      catch (Exception ex)
      {
        AnsiConsole.MarkupLine($"[red]Error:[/] {ex.Message}");
        Pause();
      }
    }
  }

  private static void Pause()
  {
    AnsiConsole.Markup("[grey]Press Enter to continue...[/]");
    Console.ReadLine();
  }

  private static void EnsureFolderValid(IAppConfig config, IServerHost server)
  {
    if (!Directory.Exists(server.CurrentStoragePath))
      Directory.CreateDirectory(server.CurrentStoragePath);
  }

  private static bool TryValidateFolder(string? path, out string reason)
  {
    reason = string.Empty;
    if (string.IsNullOrWhiteSpace(path)) { reason = "Empty path."; return false; }
    if (path.IndexOfAny(Path.GetInvalidPathChars()) >= 0) { reason = "Contains invalid characters."; return false; }
    try
    {
      var full = Path.GetFullPath(path);
      _ = full.Length;
      return true;
    }
    catch (Exception ex)
    {
      reason = ex.Message;
      return false;
    }
  }
}