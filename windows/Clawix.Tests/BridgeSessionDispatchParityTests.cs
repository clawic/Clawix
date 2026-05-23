using System.Net;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;
using Clawix.Engine.Pairing;
using Xunit;

namespace Clawix.Tests;

public sealed class BridgeSessionDispatchParityTests
{
    [Fact]
    public async Task DesktopParityFrames_ReturnExplicitResponses()
    {
        var port = ReserveLoopbackPort();
        var pairing = new PairingService(new InMemoryPairingStore(), (ushort)port);
        var host = new InMemoryEngineHost
        {
            ClawJSServiceStatusesCurrent =
            [
                new WireClawJSServiceSnapshot
                {
                    Id = "database",
                    State = "readyFromDaemon",
                    Port = 24102,
                    Pid = 12345,
                    RestartCount = 0,
                    LastError = null,
                    UpdatedAtMs = 1777000000000,
                    Source = "daemon",
                },
            ],
        };

        await using var server = new BridgeServer(
            host,
            pairing,
            bindAddress: IPAddress.Loopback,
            port: (ushort)port);
        await server.StartAsync();

        using var client = new ClientWebSocket();
        await client.ConnectAsync(new Uri($"ws://127.0.0.1:{port}"), CancellationToken.None);

        await SendAsync(client, new BridgeBody.Auth(
            pairing.Bearer,
            "Windows desktop",
            ClientKind.Desktop,
            "client-win",
            "install-win",
            "device-win"));

        Assert.IsType<BridgeBody.AuthOk>((await ReceiveAsync(client)).Body);
        Assert.IsType<BridgeBody.BridgeState>((await ReceiveAsync(client)).Body);

        await SendAsync(client, new BridgeBody.RequestClawJSServiceStatuses());
        var serviceStatuses = Assert.IsType<BridgeBody.ClawJSServiceStatusesSnapshot>((await ReceiveAsync(client)).Body);
        Assert.Single(serviceStatuses.Services);
        Assert.Equal("database", serviceStatuses.Services[0].Id);

        await SendAsync(client, new BridgeBody.RequestRolloutAttachment("rollout-attachment-1"));
        var rollout = Assert.IsType<BridgeBody.RolloutAttachmentSnapshot>((await ReceiveAsync(client)).Body);
        Assert.Equal("rollout-attachment-1", rollout.AttachmentId);
        Assert.Equal("cm9sbG91dA==", rollout.DataBase64);
        Assert.Equal("text/plain", rollout.MimeType);
        Assert.Null(rollout.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioRegister("req-register", new WireAudioRegisterRequest
        {
            Kind = WireAudioKind.UserMessage,
            AppId = "clawix",
            OriginActor = WireAudioOriginActor.User,
            MimeType = "audio/m4a",
            BytesBase64 = "ZmFrZQ==",
            DurationMs = 1200,
        }));
        var register = Assert.IsType<BridgeBody.AudioRegisterResult>((await ReceiveAsync(client)).Body);
        Assert.Equal("req-register", register.RequestId);
        Assert.Null(register.Asset);
        Assert.Equal("audio catalog unavailable", register.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioAttachTranscript("req-transcript", "audio-1", new WireAudioAttachTranscriptInput
        {
            Text = "hello",
            Role = WireAudioTranscriptRole.Transcription,
        }));
        var transcript = Assert.IsType<BridgeBody.AudioAttachTranscriptResult>((await ReceiveAsync(client)).Body);
        Assert.Equal("req-transcript", transcript.RequestId);
        Assert.Null(transcript.Transcript);
        Assert.Equal("audio catalog unavailable", transcript.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioGet("req-get", "audio-1", "clawix"));
        var get = Assert.IsType<BridgeBody.AudioGetResult>((await ReceiveAsync(client)).Body);
        Assert.Equal("req-get", get.RequestId);
        Assert.Null(get.Asset);
        Assert.Equal("audio catalog unavailable", get.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioGetBytes("req-bytes", "audio-1", "clawix"));
        var bytes = Assert.IsType<BridgeBody.AudioBytesResult>((await ReceiveAsync(client)).Body);
        Assert.Equal("req-bytes", bytes.RequestId);
        Assert.Null(bytes.AudioBase64);
        Assert.Equal("audio catalog unavailable", bytes.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioList("req-list", new WireAudioListFilter { AppId = "clawix" }));
        var list = Assert.IsType<BridgeBody.AudioListResult>((await ReceiveAsync(client)).Body);
        Assert.Equal("req-list", list.RequestId);
        Assert.Null(list.List);
        Assert.Equal("audio catalog unavailable", list.ErrorMessage);

        await SendAsync(client, new BridgeBody.AudioDelete("req-delete", "audio-1", "clawix"));
        var delete = Assert.IsType<BridgeBody.AudioDeleteResult>((await ReceiveAsync(client)).Body);
        Assert.False(delete.Deleted);
        Assert.Equal("audio catalog unavailable", delete.ErrorMessage);

        await client.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", CancellationToken.None);
        await server.StopAsync();
    }

    private static int ReserveLoopbackPort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    private static Task SendAsync(ClientWebSocket socket, BridgeBody body)
    {
        var bytes = BridgeCoder.EncodeBytes(new BridgeFrame(body));
        return socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
    }

    private static async Task<BridgeFrame> ReceiveAsync(ClientWebSocket socket)
    {
        var buffer = new byte[32 * 1024];
        using var stream = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            stream.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        return BridgeCoder.Decode(Encoding.UTF8.GetString(stream.ToArray()));
    }
}
