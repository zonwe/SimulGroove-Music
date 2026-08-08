using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;

namespace Music.Api.Services.Administration;

public interface IAdminCredentialService
{
    bool IsConfigured { get; }
    string Username { get; }
    bool Validate(string? username, string? password);
}

public sealed class AdminCredentialService(IOptions<AdministrationOptions> options) : IAdminCredentialService
{
    private readonly AdministrationOptions _options = options.Value;

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(_options.Username) &&
        !string.IsNullOrEmpty(_options.Password);

    public string Username => _options.Username.Trim().ToLowerInvariant();

    public bool Validate(string? username, string? password)
    {
        if (!IsConfigured || string.IsNullOrWhiteSpace(username) || password is null)
        {
            return false;
        }

        return FixedTimeEquals(username.Trim().ToLowerInvariant(), Username) &&
               FixedTimeEquals(password, _options.Password);
    }

    private static bool FixedTimeEquals(string actual, string expected)
    {
        var actualHash = SHA256.HashData(Encoding.UTF8.GetBytes(actual));
        var expectedHash = SHA256.HashData(Encoding.UTF8.GetBytes(expected));
        return CryptographicOperations.FixedTimeEquals(actualHash, expectedHash);
    }
}
