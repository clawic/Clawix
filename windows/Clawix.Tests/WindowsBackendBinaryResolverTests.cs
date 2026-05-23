using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class WindowsBackendBinaryResolverTests
{
    [Fact]
    public void CandidatePaths_IncludeKnownWindowsInstallLocations()
    {
        var candidates = WindowsBackendBinaryResolver.CandidatePaths(
            @"C:\Users\alice\AppData\Roaming",
            @"C:\Users\alice\AppData\Local");

        Assert.Contains(@"C:\Users\alice\AppData\Roaming/npm/codex.cmd".Replace('/', Path.DirectorySeparatorChar), candidates);
        Assert.Contains(@"C:\Users\alice\AppData\Local/pnpm/codex.cmd".Replace('/', Path.DirectorySeparatorChar), candidates);
        Assert.Contains(@"C:\Users\alice\AppData\Local/Volta/bin/codex.exe".Replace('/', Path.DirectorySeparatorChar), candidates);
    }

    [Fact]
    public void Resolve_PrefersExistingOverride()
    {
        var dir = Directory.CreateTempSubdirectory();
        try
        {
            var executable = Path.Combine(dir.FullName, "codex.cmd");
            File.WriteAllText(executable, "");

            Assert.Equal(executable, WindowsBackendBinaryResolver.Resolve(
                overridePath: executable,
                appData: Path.Combine(dir.FullName, "roaming"),
                localAppData: Path.Combine(dir.FullName, "local"),
                path: "",
                pathExt: ".CMD"));
        }
        finally
        {
            dir.Delete(recursive: true);
        }
    }

    [Fact]
    public void ResolveFromPath_FindsExecutableUsingPathext()
    {
        var dir = Directory.CreateTempSubdirectory();
        try
        {
            var executable = Path.Combine(dir.FullName, "codex.EXE");
            File.WriteAllText(executable, "");

            Assert.Equal(executable, WindowsBackendBinaryResolver.ResolveFromPath(
                path: dir.FullName,
                pathExt: ".EXE;.CMD"));
        }
        finally
        {
            dir.Delete(recursive: true);
        }
    }
}
