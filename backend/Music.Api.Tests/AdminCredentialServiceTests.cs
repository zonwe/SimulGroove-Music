using Microsoft.Extensions.Options;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using Music.Api.Services.Administration;

namespace Music.Api.Tests;

[TestClass]
public sealed class AdminCredentialServiceTests
{
    [TestMethod]
    public void ValidateAcceptsConfiguredAdministrator()
    {
        var service = Create("Admin@Example.com", "correct horse battery staple");

        Assert.IsTrue(service.IsConfigured);
        Assert.AreEqual("admin@example.com", service.Username);
        Assert.IsTrue(service.Validate(" ADMIN@example.com ", "correct horse battery staple"));
    }

    [TestMethod]
    public void ValidateRejectsWrongOrMissingCredentials()
    {
        var service = Create("admin", "expected-password");

        Assert.IsFalse(service.Validate("admin", "wrong-password"));
        Assert.IsFalse(service.Validate("other", "expected-password"));
        Assert.IsFalse(service.Validate(null, null));
        Assert.IsFalse(Create("admin", string.Empty).IsConfigured);
    }

    private static AdminCredentialService Create(string username, string password) =>
        new(Options.Create(new AdministrationOptions
        {
            Username = username,
            Password = password
        }));
}
