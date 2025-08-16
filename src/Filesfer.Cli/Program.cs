using Filesfer.Cli;
using Filesfer.Cli.Commands;
using Spectre.Console;
using Spectre.Console.Cli;

var services = new ServiceCollection();
services.AddSingleton<IServerHost, ServerHost>();

var app = new CommandApp(new TypeRegistrar(services));
app.Configure(c =>
{
  c.AddCommand<StartServerCommand>("start");
  c.AddCommand<StopServerCommand>("stop");
  c.AddCommand<StatusServerCommand>("status");
  c.AddCommand<RunServerCommand>("run-server");
});

if (args.Length == 0)
{
  AnsiConsole.Write(
      new FigletText("Filesfer")
          .Centered()
          .Color(Color.Purple));
}

return await app.RunAsync(args);
