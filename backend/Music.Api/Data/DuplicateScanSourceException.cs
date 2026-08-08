namespace Music.Api.Data;

public sealed class DuplicateScanSourceException(string sourcePath, Exception innerException)
    : Exception("The scan source path has already been configured for this account.", innerException)
{
    public string SourcePath { get; } = sourcePath;
}
