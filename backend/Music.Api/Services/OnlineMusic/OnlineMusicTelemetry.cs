using System.Diagnostics.Metrics;

namespace Music.Api.Services.OnlineMusic;

public static class OnlineMusicTelemetry
{
    public const string MeterName = "FlutterMusic.OnlineMusic";

    public static readonly Meter Meter = new(MeterName, "1.0.0");
    public static readonly Counter<long> SidecarRequests = Meter.CreateCounter<long>(
        "flutter_music.online_music.sidecar.requests",
        description: "Number of requests sent to the private online music sidecar.");
    public static readonly Counter<long> SidecarFailures = Meter.CreateCounter<long>(
        "flutter_music.online_music.sidecar.failures",
        description: "Number of failed private sidecar requests.");
    public static readonly Counter<long> CircuitRejections = Meter.CreateCounter<long>(
        "flutter_music.online_music.sidecar.circuit_rejections",
        description: "Number of sidecar requests rejected by the open circuit.");
    public static readonly Histogram<double> SidecarDuration = Meter.CreateHistogram<double>(
        "flutter_music.online_music.sidecar.duration",
        unit: "ms",
        description: "Duration of private sidecar requests in milliseconds.");
}
