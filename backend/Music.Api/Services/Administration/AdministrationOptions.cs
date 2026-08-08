namespace Music.Api.Services.Administration;

public sealed class AdministrationOptions
{
    public const string SectionName = "Administration";

    public string Username { get; init; } = string.Empty;
    public string Password { get; init; } = string.Empty;
}

public static class AdminAuthorization
{
    public const string PolicyName = "Administrator";
    public const string RoleName = "Administrator";
}
