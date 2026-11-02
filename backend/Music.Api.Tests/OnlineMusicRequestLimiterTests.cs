using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.OnlineMusic;

namespace Music.Api.Tests;

[TestClass]
public sealed class OnlineMusicRequestLimiterTests
{
    [TestMethod]
    public void AnonymousRequestsAreCountedPerIp()
    {
        var limiter = CreateLimiter(limit: 2);

        Assert.IsTrue(limiter.TryAcquireAnonymous("10.0.0.1"));
        Assert.IsTrue(limiter.TryAcquireAnonymous("10.0.0.1"));
        Assert.IsFalse(limiter.TryAcquireAnonymous("10.0.0.1"));
        Assert.IsTrue(limiter.TryAcquireAnonymous("10.0.0.2"));
    }

    [TestMethod]
    public void AnonymousRequestsWithoutIpShareOneBucket()
    {
        var limiter = CreateLimiter(limit: 1);

        Assert.IsTrue(limiter.TryAcquireAnonymous(null));
        Assert.IsFalse(limiter.TryAcquireAnonymous(string.Empty));
    }

    [TestMethod]
    public void AccountRequestsAlsoConsumeTheIpBucket()
    {
        var limiter = CreateLimiter(limit: 1);

        Assert.IsTrue(limiter.TryAcquire("alice", "10.0.0.3"));
        // 同一来源 IP 的下一次请求（无论登录还是匿名）都被 IP 桶拦截。
        Assert.IsFalse(limiter.TryAcquireAnonymous("10.0.0.3"));
        Assert.IsTrue(limiter.TryAcquire("bob", "10.0.0.4"));
    }

    private static OnlineMusicRequestLimiter CreateLimiter(int limit) =>
        new(Options.Create(new OnlineMusicOptions { RequestsPerMinute = limit }));
}
