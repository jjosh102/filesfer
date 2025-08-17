
using System.Text.Json;

namespace Filesfer.Cli;

public interface IAppConfig
{
  string StoragePath { get; set; }
  int Port { get; set; }
  void Load();
  void Save();
}

public sealed class AppConfig : IAppConfig
{
  private record ConfigData(string StoragePath, int Port);

  private readonly string _configFile =
      Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Filesfer", "config.json");

  public string StoragePath { get; set; } =
      Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "Filesfer", "Shared");

  public int Port { get; set; } = 5000;

  public void Load()
  {
    try
    {
      if (!File.Exists(_configFile))
      {
        Directory.CreateDirectory(Path.GetDirectoryName(_configFile)!);
        Save();
        return;
      }

      var json = File.ReadAllText(_configFile);
      var data = JsonSerializer.Deserialize<ConfigData>(json);
      if (data is null) return;

      StoragePath = data.StoragePath;
      Port = data.Port is > 0 and < 65536 ? data.Port : 5000;
    }
    catch
    {
      // If load fails, keep defaults.
    }
  }

  public void Save()
  {
    Directory.CreateDirectory(Path.GetDirectoryName(_configFile)!);
    var data = new ConfigData(StoragePath, Port);
    var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
    File.WriteAllText(_configFile, json);
  }
}
