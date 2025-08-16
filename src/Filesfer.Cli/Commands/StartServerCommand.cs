using Spectre.Console;
using Spectre.Console.Cli;
using System.Diagnostics;

namespace Filesfer.Cli.Commands;

public class StartServerSettings : RunServerSettings { }

public class StartServerCommand : Command<StartServerSettings>
{
  public override int Execute(CommandContext context, StartServerSettings settings)
  {
    var existingPid = PidManager.ReadPid();
    if (existingPid.HasValue && PidManager.IsProcessRunning(existingPid.Value))
    {
      AnsiConsole.MarkupLine($"[red]Server already running (PID {existingPid}).[/]");
      return -1;
    }

    if (PortProber.IsPortInUse(settings.Port))
    {
      AnsiConsole.MarkupLine($"[red]Port {settings.Port} is already in use![/]");
      return -1;
    }

    var exePath = Process.GetCurrentProcess().MainModule?.FileName;
    var psi = new ProcessStartInfo(exePath!, $"run-server --port {settings.Port} --folder \"{settings.Folder}\"")
    {
      UseShellExecute = false,
      CreateNoWindow = true
    };

    var process = Process.Start(psi);
    if (process is null)
    {
      AnsiConsole.MarkupLine("[red]Failed to start server process[/]");
      return -1;
    }

    PidManager.WritePid(process.Id);
    AnsiConsole.MarkupLine($"[green]Server started (PID {process.Id}) on port {settings.Port}[/]");
    return 0;
  }
}
