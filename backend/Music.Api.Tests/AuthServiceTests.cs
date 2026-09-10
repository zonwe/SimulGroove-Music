using System.Text;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services;

namespace Music.Api.Tests;

[TestClass]
public sealed class AuthServiceTests
{
    private TestDirectory _directory = null!;

    [TestInitialize]
    public void SetUp() => _directory = new TestDirectory();

    [TestCleanup]
    public void TearDown() => _directory.Dispose();

    [TestMethod]
    public void SignInCreatesAccountAndRefreshRotatesToken()
    {
        var service = CreateService();

        var initial = service.SignIn(" Alice@Example.com ", "correct horse battery staple");
        Assert.IsNotNull(initial);
        Assert.AreEqual("alice@example.com", initial!.Account.Username);
        Assert.AreEqual("alice", initial.Account.DisplayName);
        Assert.IsFalse(string.IsNullOrWhiteSpace(initial.TrackMatchSalt));
        Assert.IsNotNull(service.Authenticate(initial.Token));

        var rotated = service.Refresh(initial.RefreshToken);
        Assert.IsNotNull(rotated);
        Assert.AreNotEqual(initial.RefreshToken, rotated!.RefreshToken);
        Assert.AreEqual(initial.TrackMatchSalt, rotated.TrackMatchSalt);
        Assert.IsNotNull(service.Authenticate(rotated.Token));

        // A rotated token is single-use. Replaying it revokes the account's
        // remaining refresh tokens so a stolen token cannot be used silently.
        Assert.IsNull(service.Refresh(initial.RefreshToken));
        Assert.IsNull(service.Refresh(rotated.RefreshToken));
    }

    [TestMethod]
    public void TrackMatchSaltIsStablePerAccountAndDifferentAcrossAccounts()
    {
        var service = CreateService();

        var first = service.SignIn("first@example.com", "first-password")!;
        var again = service.SignIn("first@example.com", "first-password")!;
        var second = service.SignIn("second@example.com", "second-password")!;

        Assert.AreEqual(first.TrackMatchSalt, again.TrackMatchSalt);
        Assert.AreNotEqual(first.TrackMatchSalt, second.TrackMatchSalt);
    }

    [TestMethod]
    public void SignInRejectsWrongPasswordAfterAccountCreation()
    {
        var service = CreateService();

        Assert.IsNotNull(service.SignIn("user@example.com", "first-password"));
        Assert.IsNull(service.SignIn("USER@example.com", "wrong-password"));
        Assert.IsNotNull(service.SignIn("user@example.com", "first-password"));
    }

    [TestMethod]
    public void JwtValidationRejectsTamperedToken()
    {
        var jwt = new JwtTokenService(CreateConfiguration());
        var issued = jwt.Issue("alice@example.com");

        Assert.AreEqual("alice@example.com", jwt.Validate(issued.Token));

        var parts = issued.Token.Split('.');
        var replacement = parts[2][0] == 'A' ? 'B' : 'A';
        parts[2] = replacement + parts[2][1..];
        var tampered = string.Join('.', parts);
        Assert.IsNull(jwt.Validate(tampered));
        Assert.IsNull(jwt.Validate("not-a-jwt"));
    }

    private AuthService CreateService() =>
        new(CreateConfiguration(), CreateEnvironment(), new SqliteRefreshTokenStore());

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

    private IHostEnvironment CreateEnvironment() => new TestHostEnvironment(_directory.Path);
}

internal sealed class TestHostEnvironment(string contentRootPath) : IHostEnvironment
{
    public string EnvironmentName { get; set; } = Environments.Development;
    public string ApplicationName { get; set; } = "Music.Api.Tests";
    public string ContentRootPath { get; set; } = contentRootPath;
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
}

internal sealed class TestDirectory : IDisposable
{
    public TestDirectory()
    {
        Path = System.IO.Directory.CreateTempSubdirectory("music-api-tests-").FullName;
    }

    public string Path { get; }

    public void Dispose()
    {
        SqliteConnection.ClearAllPools();
        if (Directory.Exists(Path)) Directory.Delete(Path, recursive: true);
    }
}
