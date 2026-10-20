using Microsoft.Extensions.Options;

namespace Music.Api.Services.OnlineMusic;

/// <summary>
/// 进程内熔断器，按 sidecar 操作分别计数。
///
/// 关键设计：熔断状态必须按操作隔离。搜索、解析、播放流、歌词、封面、下载共用同一个
/// sidecar，但它们的失败原因互不相关——一次批量封面拉取失败不应该让搜索功能停摆。
/// 早期实现用单一全局计数器，导致封面 5xx 达到阈值后搜索直接返回"服务不可用"。
///
/// 另外，只有瞬时故障（网络、超时、上游 5xx）才会走到 <see cref="RecordFailure"/>：
/// sidecar 对"这首歌没有封面/无法解析"这类稳定业务结果返回 4xx，
/// <see cref="OnlineMusicResilienceHandler"/> 不会把它计为失败。
/// </summary>
public sealed class OnlineMusicCircuitBreaker
{
    private readonly object _sync = new();
    private readonly ILogger<OnlineMusicCircuitBreaker> _logger;
    private readonly TimeProvider _timeProvider;
    private readonly int _failureThreshold;
    private readonly TimeSpan _breakDuration;
    private readonly Dictionary<string, CircuitState> _circuits = new(StringComparer.Ordinal);

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

    public OnlineMusicCircuitLease Enter(string operation)
    {
        var name = Normalize(operation);
        lock (_sync)
        {
            var state = State(name);
            var now = _timeProvider.GetUtcNow();
            if (state.OpenUntil is { } openUntil)
            {
                if (openUntil > now || state.ProbeInFlight)
                {
                    throw new OnlineMusicCircuitOpenException(
                        name,
                        openUntil > now ? openUntil - now : TimeSpan.Zero);
                }

                state.ProbeInFlight = true;
                return new OnlineMusicCircuitLease(name, IsRecoveryProbe: true);
            }

            return new OnlineMusicCircuitLease(name, IsRecoveryProbe: false);
        }
    }

    public void RecordSuccess(OnlineMusicCircuitLease lease)
    {
        lock (_sync)
        {
            var state = State(lease.Operation);
            var recovered = state.OpenUntil is not null;
            state.ConsecutiveFailures = 0;
            state.OpenUntil = null;
            state.ProbeInFlight = false;
            if (recovered)
            {
                _logger.LogInformation(
                    "Online music sidecar circuit recovered for operation {Operation}.",
                    lease.Operation);
            }
        }
    }

    public void RecordFailure(OnlineMusicCircuitLease lease)
    {
        lock (_sync)
        {
            var state = State(lease.Operation);
            state.ProbeInFlight = false;
            state.ConsecutiveFailures++;
            if (!lease.IsRecoveryProbe && state.ConsecutiveFailures < _failureThreshold)
            {
                return;
            }

            state.ConsecutiveFailures = 0;
            state.OpenUntil = _timeProvider.GetUtcNow() + _breakDuration;
            _logger.LogWarning(
                "Online music sidecar circuit opened for operation {Operation} for {BreakSeconds} seconds.",
                lease.Operation,
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
            State(lease.Operation).ProbeInFlight = false;
        }
    }

    private CircuitState State(string operation)
    {
        if (_circuits.TryGetValue(operation, out var state)) return state;
        state = new CircuitState();
        _circuits[operation] = state;
        return state;
    }

    private static string Normalize(string? operation) =>
        string.IsNullOrWhiteSpace(operation) ? OnlineMusicOperations.Other : operation;

    private sealed class CircuitState
    {
        public int ConsecutiveFailures;
        public DateTimeOffset? OpenUntil;
        public bool ProbeInFlight;
    }
}

public readonly record struct OnlineMusicCircuitLease(string Operation, bool IsRecoveryProbe);

public sealed class OnlineMusicCircuitOpenException(string operation, TimeSpan retryAfter)
    : HttpRequestException($"Online music sidecar circuit is open for operation '{operation}'.")
{
    public string Operation { get; } = operation;

    public TimeSpan RetryAfter { get; } = retryAfter;
}
