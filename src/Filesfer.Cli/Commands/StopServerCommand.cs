using Spectre.Console;
using Spectre.Console.Cli;
using System.Diagnostics;
namespace Filesfer.Cli.Commands;

public class StopServerCommand : Command<CommandSettings>
{
  public override int Execute(CommandContext context, CommandSettings settings)
  {
    var pid = PidManager.ReadPid();
    if (!pid.HasValue)
    {
      AnsiConsole.MarkupLine("[yellow]No PID file found. Server not running?[/]");
      return 0;
    }

    if (PidManager.IsProcessRunning(pid.Value))
    {
      try
      {
        var process = Process.GetProcessById(pid.Value);
        process.Kill(true);
        process.WaitForExit();
        AnsiConsole.MarkupLine($"[green]Stopped server process (PID {pid.Value})[/]");
      }
      catch
      {
        AnsiConsole.MarkupLine($"[red]Failed to stop process {pid.Value}[/]");
      }
    }
    else
    {
      AnsiConsole.MarkupLine("[yellow]Server process not running[/]");
    }

    PidManager.RemovePid();
    return 0;
  }
}
