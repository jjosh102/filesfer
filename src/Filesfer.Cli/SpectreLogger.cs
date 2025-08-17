
using Spectre.Console;

namespace Filesfer.Cli;
public class SpectreLoggerProvider : ILoggerProvider
{
  public ILogger CreateLogger(string categoryName) => new SpectreLogger(categoryName);

  public void Dispose() { }
}

public class SpectreLogger : ILogger
{
  private readonly string _category;

  public SpectreLogger(string category)
  {
    _category = category;
  }

  IDisposable? ILogger.BeginScope<TState>(TState state)
  {
    return null;
  }

  public bool IsEnabled(LogLevel logLevel) => true;

  public void Log<TState>(
      LogLevel logLevel, EventId eventId, TState state,
      Exception? exception, Func<TState, Exception?, string> formatter)
  {
    var message = formatter(state, exception);

    var levelColor = logLevel switch
    {
      LogLevel.Trace => "gray",
      LogLevel.Debug => "blue",
      LogLevel.Information => "green",
      LogLevel.Warning => "yellow",
      LogLevel.Error => "red",
      LogLevel.Critical => "bold red",
      _ => "white"
    };

    AnsiConsole.MarkupLine($"[gray][[{DateTime.Now:T}]][/]" +
        $" [{levelColor}]{logLevel,11}[/] " +
        $"[[{_category}]] {message}");
  }
}
