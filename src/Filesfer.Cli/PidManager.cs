using System.Diagnostics;

namespace Filesfer.Cli;

public static class PidManager
{
  private static readonly string PidFile = Path.Combine(AppContext.BaseDirectory, "filesfer.pid");

  public static void WritePid(int pid) =>
      File.WriteAllText(PidFile, pid.ToString());

  public static int? ReadPid()
  {
    if (!File.Exists(PidFile))
      return null;

    var text = File.ReadAllText(PidFile);
    if (int.TryParse(text, out var pid))
      return pid;

    return null;
  }

  public static void RemovePid()
  {
    if (File.Exists(PidFile))
      File.Delete(PidFile);
  }

  public static bool IsProcessRunning(int pid)
  {
    try
    {
      var process = Process.GetProcessById(pid);
      return !process.HasExited;
    }
    catch
    {
      return false;
    }
  }
}