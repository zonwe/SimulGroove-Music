using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Music.Api.Data;
using Music.Api.Models;
using Music.Api.Services.Administration;
using Music.Api.Services.Scanning;

namespace Music.Api.Pages.Admin.Scanning;

[Authorize(Policy = AdminAuthorization.PolicyName)]
public sealed class IndexModel(IMusicScanService scanner, IAuditLogStore audit) : PageModel
{
    public static readonly IReadOnlyList<int> Intervals = [15, 30, 60, 360, 720, 1440, 10080];

    [BindProperty]
    public CreateSourceInput NewSource { get; set; } = new();

    [TempData]
    public string? SuccessMessage { get; set; }

    [TempData]
    public string? ErrorMessage { get; set; }

    public IReadOnlyList<ScanSourceResponse> Sources { get; private set; } = [];
    public ScanSourceResponse? SelectedSource { get; private set; }
    public IReadOnlyList<ScannedTrackResponse> SelectedTracks { get; private set; } = [];

    private string Username => User.Identity?.Name ?? throw new InvalidOperationException("Administrator identity is missing.");

    public void OnGet(string? tracksFor = null) => LoadPage(tracksFor);

    public IActionResult OnGetStream(string sourceId, string trackId)
    {
        var track = scanner.OpenTrackFile(Username, sourceId, trackId);
        if (track is null) return NotFound();

        Response.Headers.CacheControl = "private, no-store";
        Response.Headers["X-Content-Type-Options"] = "nosniff";
        return new FileStreamResult(track.Content, track.ContentType)
        {
            EnableRangeProcessing = true,
            LastModified = track.ModifiedAt
        };
    }

    public async Task<IActionResult> OnPostCreateAsync(CancellationToken cancellationToken)
    {
        if (!ModelState.IsValid)
        {
            LoadPage(null);
            return Page();
        }

        try
        {
            var source = scanner.CreateSource(
                Username,
                new CreateScanSourceRequest(NewSource.Path, NewSource.IntervalMinutes, NewSource.Enabled));

            Record("scan.source.created", $"Administrator created scan source {source.Path}.", source.Id);

            var result = await scanner.ScanNowAsync(Username, source.Id, cancellationToken);
            Record("scan.manual", $"Administrator initial scan finished with status {result?.Status ?? "missing"}.", source.Id, result?.TrackCount);

            if (result?.Status == "failed")
            {
                ErrorMessage = $"路径已添加，但首次扫描失败：{FriendlyError(result.LastError)}";
            }
            else
            {
                SuccessMessage = $"路径已添加，首次扫描完成，共索引 {result?.TrackCount ?? 0} 首曲目。";
            }

            return RedirectToPage(new { tracksFor = source.Id });
        }
        catch (ArgumentException exception)
        {
            ModelState.AddModelError("NewSource.Path", FriendlyError(exception.Message));
        }
        catch (DuplicateScanSourceException)
        {
            ModelState.AddModelError("NewSource.Path", "该扫描路径已经配置过了。");
        }

        LoadPage(null);
        return Page();
    }

    public async Task<IActionResult> OnPostScanAsync(string sourceId, CancellationToken cancellationToken)
    {
        var result = await scanner.ScanNowAsync(Username, sourceId, cancellationToken);
        if (result is null)
        {
            ErrorMessage = "扫描路径不存在或已被删除。";
            return RedirectToPage();
        }

        Record("scan.manual", $"Administrator manual scan finished with status {result.Status}.", result.Id, result.TrackCount);
        if (result.Status == "failed")
        {
            ErrorMessage = $"扫描失败：{FriendlyError(result.LastError)}";
        }
        else
        {
            SuccessMessage = $"扫描完成，共索引 {result.TrackCount} 首曲目。";
        }

        return RedirectToPage(new { tracksFor = result.Id });
    }

    public IActionResult OnPostToggle(string sourceId, bool enabled)
    {
        var updated = scanner.UpdateSource(
            Username,
            sourceId,
            new UpdateScanSourceRequest(null, null, enabled));
        if (updated is null)
        {
            ErrorMessage = "扫描路径不存在或已被删除。";
        }
        else
        {
            Record("scan.source.updated", $"Administrator {(enabled ? "enabled" : "disabled")} scan source {updated.Path}.", updated.Id);
            SuccessMessage = enabled ? "定时扫描已启用。" : "定时扫描已暂停。";
        }

        return RedirectToPage();
    }

    public IActionResult OnPostUpdate(string sourceId, string? path, int intervalMinutes)
    {
        try
        {
            var updated = scanner.UpdateSource(
                Username,
                sourceId,
                new UpdateScanSourceRequest(path, intervalMinutes, null));
            if (updated is null)
            {
                ErrorMessage = "扫描路径不存在或已被删除。";
            }
            else
            {
                Record("scan.source.updated", $"Administrator updated scan source {updated.Path}.", updated.Id);
                SuccessMessage = "扫描路径已更新。";
            }
        }
        catch (ArgumentException exception)
        {
            ErrorMessage = FriendlyError(exception.Message);
        }
        catch (DuplicateScanSourceException)
        {
            ErrorMessage = "该扫描路径已经配置过了。";
        }

        return RedirectToPage(new { tracksFor = sourceId });
    }

    public IActionResult OnPostDelete(string sourceId)
    {
        var source = scanner.GetSources(Username).FirstOrDefault(value => value.Id == sourceId);
        if (source is null || !scanner.DeleteSource(Username, sourceId))
        {
            ErrorMessage = "扫描路径不存在或已被删除。";
        }
        else
        {
            Record("scan.source.deleted", $"Administrator deleted scan source {source.Path}.", source.Id);
            SuccessMessage = "扫描路径和服务器索引已删除，音频文件未受影响。";
        }

        return RedirectToPage();
    }

    public static string StatusLabel(string status) => status switch
    {
        "idle" => "空闲",
        "scanning" => "扫描中",
        "failed" => "失败",
        _ => status
    };

    public static string StatusClass(string status) => status switch
    {
        "idle" => "badge-idle",
        "scanning" => "badge-scanning",
        "failed" => "badge-failed",
        _ => string.Empty
    };

    public static string IntervalLabel(int minutes)
    {
        if (minutes < 60) return $"每 {minutes} 分钟";
        if (minutes % 1440 == 0) return $"每 {minutes / 1440} 天";
        return $"每 {minutes / 60} 小时";
    }

    public static string DateLabel(DateTimeOffset? value) =>
        value?.ToLocalTime().ToString("MM-dd HH:mm") ?? "尚未扫描";

    private void LoadPage(string? tracksFor)
    {
        Sources = scanner.GetSources(Username);
        if (string.IsNullOrWhiteSpace(tracksFor)) return;

        SelectedSource = Sources.FirstOrDefault(source => source.Id == tracksFor);
        if (SelectedSource is not null)
        {
            SelectedTracks = scanner.GetTracks(Username, SelectedSource.Id, 500);
        }
    }

    private void Record(string eventType, string message, string sourceId, int? trackCount = null)
    {
        audit.Record(new AuditLogEntry(
            Username,
            "information",
            eventType,
            message,
            DateTimeOffset.UtcNow,
            Details: JsonSerializer.Serialize(new { sourceId, trackCount })));
    }

    private static string FriendlyError(string? message)
    {
        if (string.IsNullOrWhiteSpace(message)) return "未知错误。";
        if (message.Contains("does not exist", StringComparison.OrdinalIgnoreCase) ||
            message.Contains("not accessible", StringComparison.OrdinalIgnoreCase))
        {
            return "目录不存在，或 Music.Api 进程没有访问权限。";
        }

        if (message.Contains("outside the configured scanning roots", StringComparison.OrdinalIgnoreCase))
        {
            return "该目录不在后端 Scanning:AllowedRoots 允许范围内。";
        }

        return message;
    }

    public sealed class CreateSourceInput
    {
        [Required(ErrorMessage = "请输入后端服务器上的绝对路径。")]
        [Display(Name = "服务器绝对路径")]
        public string Path { get; set; } = string.Empty;

        [Range(1, 10080, ErrorMessage = "扫描周期必须在 1 到 10080 分钟之间。")]
        [Display(Name = "自动扫描周期")]
        public int IntervalMinutes { get; set; } = 60;

        public bool Enabled { get; set; } = true;
    }
}
