using Filesfer.Tool;
using Spectre.Console;

var configBuilder = new ConfigurationBuilder()
    .AddUserSecrets<Program>()
    .AddEnvironmentVariables();

var config = configBuilder.Build();
var sharedFolder = config["SharedFolderPath"] ?? throw new InvalidOperationException("SharedFolderPath is not set in user secrets or environment variables.");
var events = new List<string>();
var server = new TcpServerService(sharedFolder);

server.OnEvent += msg =>
{
    events.Add($"{DateTime.Now:HH:mm:ss} - {msg}");
    AnsiConsole.MarkupLine($"[gray][[{DateTime.Now:T}]][/][yellow] {msg}[/]");
    if (events.Count > 50) events.RemoveAt(0);
};

ShowBanner();

while (true)
{
    var command = AnsiConsole.Prompt(
     new TextPrompt<string>("[green]Command[/] ([yellow]start[/], [yellow]stop[/], [yellow]list[/], [red]exit[/]):")
         .PromptStyle("green")
         .Validate(cmd =>
             (cmd == "start" || cmd == "stop" || cmd == "list" || cmd == "exit")
                 ? ValidationResult.Success()
                 : ValidationResult.Error("Invalid command. Please enter start, stop, list, or exit.")
         )
         .DefaultValue("list")
         .ShowDefaultValue()
 ).Trim().ToLower();

    switch (command)
    {
        case "start":
            if (server.IsRunning)
            {
                AnsiConsole.MarkupLine("[red]Server is already running![/]");
            }
            else
            {
                int port = AnsiConsole.Ask<int>("Enter port number:");
                server.Start(port);
            }
            break;

        case "stop":
            if (!server.IsRunning)
            {
                AnsiConsole.MarkupLine("[yellow]Server is not running.[/]");
            }
            else
            {
                server.Stop();
            }
            break;

        case "list":
            var files = Directory.GetFiles(sharedFolder)
                                 .Select(Path.GetFileName)
                                 .ToArray();

            if (files.Length == 0)
            {
                AnsiConsole.MarkupLine("[yellow]No files found in shared folder.[/]");
            }
            else
            {
                var table = new Table()
                    .Border(TableBorder.Rounded)
                    .BorderColor(Color.Blue)
                    .AddColumn("[yellow]Files in Shared Folder[/]");

                foreach (var file in files)
                    table.AddRow(file!);

                AnsiConsole.Write(table);
            }
            break;

        case "exit":
            if (server.IsRunning) server.Stop();
            return;
    }
}

static void ShowBanner()
{
    var rule = new Rule("[yellow]Filesfer Tool[/]").RuleStyle("green").Centered();
    AnsiConsole.Write(rule);
    AnsiConsole.MarkupLine("[blue]Welcome to the TCP Server Tool![/]");
    AnsiConsole.MarkupLine("[dim]Use commands to start, stop, and monitor the server.[/]");
    AnsiConsole.WriteLine();
}

