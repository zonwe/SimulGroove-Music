using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicTelemetryTests
{
    [TestMethod]
    public void MetricNamesRemainCompatibleWithProductionAlertRules()
    {
        Assert.AreEqual(
            "flutter_music.online_music.sidecar.requests",
            OnlineMusicTelemetry.SidecarRequests.Name);
        Assert.AreEqual(
            "flutter_music.online_music.sidecar.failures",
            OnlineMusicTelemetry.SidecarFailures.Name);
        Assert.AreEqual(
            "flutter_music.online_music.sidecar.circuit_rejections",
            OnlineMusicTelemetry.CircuitRejections.Name);
        Assert.AreEqual(
            "flutter_music.online_music.sidecar.duration",
            OnlineMusicTelemetry.SidecarDuration.Name);
        Assert.AreEqual("ms", OnlineMusicTelemetry.SidecarDuration.Unit);
    }
}
