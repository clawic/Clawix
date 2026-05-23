using Clawix.Bridged;
using Xunit;

namespace Clawix.Tests;

public sealed class ClawJSServiceStatusCatalogTests
{
    [Fact]
    public void InitialSnapshot_UsesMacServiceIdsAndStablePorts()
    {
        var services = ClawJSServiceStatusCatalog.InitialSnapshot(1777000000000);

        Assert.Collection(
            services.OrderBy(service => service.Port),
            service => AssertService(service, "runtime", 24100),
            service => AssertService(service, "sessions", 24101),
            service => AssertService(service, "database", 24102),
            service => AssertService(service, "secrets", 24103),
            service => AssertService(service, "drive", 24104),
            service => AssertService(service, "memory", 24105),
            service => AssertService(service, "index", 24106),
            service => AssertService(service, "publishing", 24111),
            service => AssertService(service, "telegram", 24150),
            service => AssertService(service, "audio", 24151),
            service => AssertService(service, "iot", 24152));
    }

    [Fact]
    public void BackendBackedServiceState_OnlyClaimsRuntimeAndSessions()
    {
        var runtime = ClawJSServiceStatusCatalog.ForBackendBackedService("runtime", "readyFromDaemon", updatedAtMs: 1777000001000);
        var sessions = ClawJSServiceStatusCatalog.ForBackendBackedService("sessions", "readyFromDaemon", updatedAtMs: 1777000001000);

        Assert.True(ClawJSServiceStatusCatalog.IsBackendBacked("runtime"));
        Assert.True(ClawJSServiceStatusCatalog.IsBackendBacked("sessions"));
        Assert.False(ClawJSServiceStatusCatalog.IsBackendBacked("secrets"));
        Assert.Equal("readyFromDaemon", runtime.State);
        Assert.Equal(24100, runtime.Port);
        Assert.Equal("readyFromDaemon", sessions.State);
        Assert.Equal(24101, sessions.Port);
    }

    private static void AssertService(Clawix.Core.Models.WireClawJSServiceSnapshot service, string id, int port)
    {
        Assert.Equal(id, service.Id);
        Assert.Equal(port, service.Port);
        Assert.Equal("availableOnDemand", service.State);
        Assert.Equal("daemon", service.Source);
        Assert.NotNull(service.LastError);
    }
}
