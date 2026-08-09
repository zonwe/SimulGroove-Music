using Microsoft.Extensions.Options;

namespace Music.Api.Services.OnlineMusic;

public sealed class OnlineMusicCircuitBreaker
{
    private readonly object _sync = new();
    private readonly ILogger<OnlineMusicCircuitBreaker> _logger;
    private readonly TimeProvider _timeProvider;
    private readonly int _failureThreshold;
    private readonly TimeSpan _breakDuration;

    private int _consecutiveFailures;
    private DateTimeOffset? _openUntil;
    private bool _probeInFlight;

    public OnlineMusicCircuitBreaker(
        IOptions<OnlineMusicOptions> options,
        ILogger<OnlineMusicCircuitBreaker> logger,
        TimeProvider timeProvider)
    {
        var settings = options.Value;
        _logger = logger;
        _timeProvider = timeProvider;
        _failureThreshold = Math.Clamp(settings.CircuitBreakerFailureThreshold, 2, 20);
        _breakDuration = TimeSpan.FromSeconds(
            Math.Clamp(settings.CircuitBreakerBreakSeconds, 5, 300));
    }

    public OnlineMusicCircuitLease Enter()
    {
        lock (_sync)
        {
            var now = _timeProvider.GetUtcNow();
            if (_openUntil is { } openUntil)
            {
                if (openUntil > now || _probeInFlight)
                {
                    throw new OnlineMusicCircuitOpenException(
                        openUntil > now ? openUntil - now : TimeSpan.Zero);
                }

                _probeInFlight = true;
                return new OnlineMusicCircuitLease(IsRecoveryProbe: true);
            }

            return new OnlineMusicCircuitLease(IsRecoveryProbe: false);
        }
    }

    public void RecordSuccess(OnlineMusicCircuitLease lease)
    {
        lock (_sync)
        {
            var recovered = _openUntil is not null;
            _consecutiveFailures = 0;
            _openUntil = null;
            _probeInFlight = false;
            if (recovered)
            {
                _logger.LogInformation("Online music sidecar circuit recovered.");
            }
        }
    }

    public void RecordFailure(OnlineMusicCircuitLease lease)
    {
        lock (_sync)
        {
            _probeInFlight = false;
            _consecutiveFailures++;
            if (!lease.IsRecoveryProbe && _consecutiveFailures < _failureThreshold)
            {
                return;
            }

            _consecutiveFailures = 0;
            _openUntil = _timeProvider.GetUtcNow() + _breakDuration;
            _logger.LogWarning(
                "Online music sidecar circuit opened for {BreakSeconds} seconds.",
                (int)_breakDuration.TotalSeconds);
        }
    }

    public void Release(OnlineMusicCircuitLease lease)
    {
        if (!lease.IsRecoveryProbe)
        {
            return;
        }

        lock (_sync)
        {
            _probeInFlight = false;
        }
    }
}

public readonly record struct OnlineMusicCircuitLease(bool IsRecoveryProbe);

public sealed class OnlineMusicCircuitOpenException(TimeSpan retryAfter)
    : HttpRequestException("Online music sidecar circuit is open.")
{
    public TimeSpan RetryAfter { get; } = retryAfter;
}
