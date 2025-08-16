using Spectre.Console;
using Spectre.Console.Cli;

namespace Filesfer.Cli.Commands;

public class StatusServerCommand : Command<CommandSettings>
{
  public override int Execute(CommandContext context, CommandSettings settings)
  {
    var pid = PidManager.ReadPid();
    if (pid.HasValue && PidManager.IsProcessRunning(pid.Value))
    {
      AnsiConsole.MarkupLine($"[green]Server is running (PID {pid.Value})[/]");
    }
    else
    {
      AnsiConsole.MarkupLine("[yellow]Server not running[/]");
    }

    return 0;
  }
}
