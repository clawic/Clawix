namespace Clawix.App.Services;

internal static class BridgeEndpoint
{
    public const string LoopbackHost = "127.0.0.1";

    public static Uri WebSocketUri(int port)
    {
        return new UriBuilder("ws", LoopbackHost, port, "/").Uri;
    }
}
