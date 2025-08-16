
using System.Net;
using System.Net.Sockets;

namespace Filesfer.Cli;


public static class PortProber
{
  public static bool IsPortInUse(int port)
  {
    try
    {
      using var client = new TcpClient();
      var result = client.BeginConnect(IPAddress.Loopback, port, null, null);
      bool success = result.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(300));
      return success && client.Connected;
    }
    catch
    {
      return false;
    }
  }
}