using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Data;
using Music.Api.Services;

namespace Music.Api.Tests;

[TestClass]
public sealed class SqliteScanSourceStoreTests
{
    private TestDirectory _directory = null!;

    [TestInitialize]
    public void SetUp() => _directory = new TestDirectory();

    [TestCleanup]
    public void TearDown() => _directory.Dispose();

    [TestMethod]
    public void CreateProvisionsAdministratorAccountAndReturnsVisibleSource()
    {
        var configuration = CreateConfiguration();
        var environment = new TestHostEnvironment(_directory.Path);
        var store = new SqliteScanSourceStore(configuration, environment);

        var created = store.Create("admin", @"D:\MusicDownload", 60, true);

        var sources = store.GetForUser("admin");
        Assert.AreEqual(1, sources.Count);
        Assert.AreEqual(created.Id, sources[0].Id);
        Assert.AreEqual(@"D:\MusicDownload", sources[0].Path);

        // The placeholder account remains compatible with normal API sign-in.
        var auth = new AuthService(configuration, environment, new SqliteRefreshTokenStore());
        Assert.IsNotNull(auth.SignIn("admin", "first-password"));
    }

    [TestMethod]
    public void CreateReportsDuplicateOnlyForSameAccountAndPath()
    {
        var store = new SqliteScanSourceStore(
            CreateConfiguration(),
            new TestHostEnvironment(_directory.Path));

        store.Create("admin", @"D:\MusicDownload", 60, true);

        Assert.ThrowsException<DuplicateScanSourceException>(() =>
            store.Create("admin", @"d:\musicdownload", 30, false));

        var otherAccountSource = store.Create("other", @"D:\MusicDownload", 60, true);
        Assert.AreEqual(otherAccountSource.Id, store.GetForUser("other").Single().Id);
        Assert.AreEqual(1, store.GetForUser("admin").Count);
    }

    private IConfiguration CreateConfiguration() => new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["Database:Path"] = Path.Combine(_directory.Path, "music.db"),
            ["Auth:JwtKey"] = "test-only-secret-key-with-at-least-32-bytes",
            ["Auth:Issuer"] = "test-issuer",
            ["Auth:Audience"] = "test-audience",
            ["Auth:AccessTokenMinutes"] = "15",
            ["Auth:RefreshTokenDays"] = "30"
        })
        .Build();
}
