using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace Music.Api.Services.OnlineMusic;

public interface IOnlineMusicRequestLimiter
{
    bool TryAcquire(string username, string? ipAddress);
}

public sealed class OnlineMusicRequestLimiter(IOptions<OnlineMusicOptions> options) : IOnlineMusicRequestLimiter
{
    private readonly ConcurrentDictionary<string, WindowCounter> _counters = new(StringComparer.Ordinal);
    private readonly int _limit = Math.Clamp(options.Value.RequestsPerMinute, 1, 600);

    public bool TryAcquire(string username, string? ipAddress)
    {
        var now = DateTimeOffset.UtcNow;
        if (!TryAcquire($"account:{username}", now)) return false;
        return string.IsNullOrWhiteSpace(ipAddress) || TryAcquire($"ip:{ipAddress}", now);
    }

    private bool TryAcquire(string key, DateTimeOffset now)
    {
        var counter = _counters.GetOrAdd(key, _ => new WindowCounter(now));
        lock (counter)
        {
            if (now - counter.StartedAt >= TimeSpan.FromMinutes(1))
            {
                counter.StartedAt = now;
                counter.Count = 0;
            }
            if (counter.Count >= _limit) return false;
            counter.Count++;
            return true;
        }
    }

    private sealed class WindowCounter(DateTimeOffset startedAt)
    {
        public DateTimeOffset StartedAt { get; set; } = startedAt;
        public int Count { get; set; }
    }
}
