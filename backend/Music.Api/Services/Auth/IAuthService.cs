using Music.Api.Models;

namespace Music.Api.Services;

public interface IAuthService
{
    AuthTokenResponse? SignIn(string username, string password);
    AuthTokenResponse? Refresh(string refreshToken);
    AccountResponse? Authenticate(string? accessToken);
    bool RevokeAll(string accessToken);
}
