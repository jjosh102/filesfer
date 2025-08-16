using Spectre.Console.Cli;

namespace Filesfer.Cli.Commands;

public class RunServerSettings : CommandSettings
{
  [CommandOption("-p|--port <PORT>")]
  public int Port { get; set; } = 5000;

  [CommandOption("-f|--folder <FOLDER>")]
  public string Folder { get; set; } = "SharedFiles";
}

public class RunServerCommand : AsyncCommand<RunServerSettings>
{
  private readonly IServerHost _serverHost;

  public RunServerCommand(IServerHost serverHost)
  {
    _serverHost = serverHost;
  }

  public override async Task<int> ExecuteAsync(CommandContext context, RunServerSettings settings)
  {
    await _serverHost.StartAsync(settings.Port, settings.Folder);
    return 0;
  }
}
