namespace Music.Api.Services.Scanning;

public sealed class ScheduledMusicScanWorker : BackgroundService
{
    private readonly IMusicScanService _scanner;
    private readonly ILogger<ScheduledMusicScanWorker> _logger;
    private readonly TimeSpan _pollInterval;

    public ScheduledMusicScanWorker(IMusicScanService scanner, IConfiguration configuration, ILogger<ScheduledMusicScanWorker> logger)
    {
        _scanner = scanner;
        _logger = logger;
        _pollInterval = TimeSpan.FromSeconds(Math.Clamp(configuration.GetValue("Scanning:PollSeconds", 30), 5, 3600));
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await _scanner.ScanDueAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                _logger.LogError(exception, "Scheduled music scan failed.");
            }

            await Task.Delay(_pollInterval, stoppingToken);
        }
    }
}
