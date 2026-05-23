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
            ProjectsCurrent =
            [
                new WireProject
                {
                    Id = "project-1",
                    Title = "Windows Parity",
                    Cwd = @"C:\src\clawix",
                    HasGitRepo = true,
                    Branch = "main",
                    LastUsedAt = DateTimeOffset.Parse("2026-05-23T00:00:00Z"),
                },
            ],
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

        await SendAsync(client, new BridgeBody.ListProjects());
        var projects = Assert.IsType<BridgeBody.ProjectsSnapshot>((await ReceiveAsync(client)).Body);
        Assert.Single(projects.Projects);
        Assert.Equal("Windows Parity", projects.Projects[0].Title);
        Assert.True(projects.Projects[0].HasGitRepo);

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

    [Fact]
    public async Task HostEvents_PushBridgeFramesToAuthenticatedDesktopClients()
    {
        var port = ReserveLoopbackPort();
        var pairing = new PairingService(new InMemoryPairingStore(), (ushort)port);
        var host = new InMemoryEngineHost();

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

        await SendAsync(client, new BridgeBody.OpenSession("session-1", null));
        Assert.IsType<BridgeBody.MessagesSnapshot>((await ReceiveAsync(client)).Body);

        host.SetSessions([
            new WireSession
            {
                Id = "session-1",
                Title = "Parity",
                CreatedAt = DateTimeOffset.Parse("2026-05-23T00:00:00Z"),
            },
        ]);
        var sessions = Assert.IsType<BridgeBody.SessionsSnapshot>((await ReceiveAsync(client)).Body);
        Assert.Single(sessions.Sessions);

        host.PublishMessage(new MessagesEvent.Appended
        {
            SessionId = "session-1",
            Message = new WireMessage
            {
                Id = "message-1",
                Role = WireRole.Assistant,
                Content = "hello",
                Timestamp = DateTimeOffset.Parse("2026-05-23T00:00:01Z"),
            },
        });
        var appended = Assert.IsType<BridgeBody.MessageAppended>((await ReceiveAsync(client)).Body);
        Assert.Equal("message-1", appended.Message.Id);

        host.PublishMessage(new MessagesEvent.Streaming
        {
            SessionId = "session-1",
            MessageId = "message-1",
            Content = "hello world",
            ReasoningText = "thinking",
            Finished = false,
        });
        var streaming = Assert.IsType<BridgeBody.MessageStreaming>((await ReceiveAsync(client)).Body);
        Assert.Equal("hello world", streaming.Content);

        host.SetRateLimits(
            new WireRateLimitSnapshot
            {
                LimitId = "codex",
                Primary = new WireRateLimitWindow
                {
                    UsedPercent = 20,
                    ResetsAt = 1777000000,
                    WindowDurationMins = 60,
                },
            },
            new Dictionary<string, WireRateLimitSnapshot>());
        Assert.IsType<BridgeBody.RateLimitsUpdated>((await ReceiveAsync(client)).Body);

        host.SetClawJSServiceStatus(new WireClawJSServiceSnapshot
        {
            Id = "secrets",
            State = "ready",
            Port = 24108,
            RestartCount = 1,
            UpdatedAtMs = 1777000001000,
            Source = "daemon",
        });
        var service = Assert.IsType<BridgeBody.ClawJSServiceStatusUpdated>((await ReceiveAsync(client)).Body);
        Assert.Equal("secrets", service.Service.Id);
        Assert.Equal("ready", service.Service.State);

        host.SetState(new BridgeRuntimeState.Error("boom"));
        var state = Assert.IsType<BridgeBody.BridgeState>((await ReceiveAsync(client)).Body);
        Assert.Equal("error", state.State);
        Assert.Equal("boom", state.Message);

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
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        var buffer = new byte[32 * 1024];
        using var stream = new MemoryStream();
        WebSocketReceiveResult result;
        do
        {
            result = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), timeout.Token);
            stream.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        return BridgeCoder.Decode(Encoding.UTF8.GetString(stream.ToArray()));
    }
}
