using Music.Api.Models;
using Music.Api.Services;
using Music.Api.Services.OnlineMusic;
using Music.Api.Tools;

namespace Music.Api.Endpoints;

public static class OnlineMusicEndpoints
{
    private const int MaxQueryLength = 100;
    private const int MaxSourceCount = 8;

    public static IEndpointRouteBuilder MapOnlineMusicEndpoints(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapGet("/api/online-music/sources", (
            HttpRequest request,
            IAuthService auth,
            IOnlineMusicSearchService search) =>
        {
            if (auth.Authenticate(request.ReadBearerToken()) is null) return Results.Unauthorized();
            return Results.Ok(new OnlineMusicSourcesResponse(search.Enabled, search.AllowedSources));
        });

        endpoints.MapPost("/api/online-music/search", async (
            OnlineMusicSearchRequest request,
            HttpContext httpContext,
            IAuthService auth,
            IOnlineMusicSearchService search,
            IOnlineMusicRequestLimiter limiter,
            CancellationToken cancellationToken) =>
        {
            var account = auth.Authenticate(httpContext.Request.ReadBearerToken());
            if (account is null) return Results.Unauthorized();

            if (!search.Enabled)
            {
                return Results.Json(
                    new ProblemResponse("online_music_source_unavailable", "在线音乐服务暂时不可用。"),
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }

            if (!limiter.TryAcquire(account.Username, httpContext.Connection.RemoteIpAddress?.ToString()))
            {
                return Results.Json(
                    new ProblemResponse("online_music_rate_limited", "在线搜索请求过于频繁，请稍后重试。"),
                    statusCode: StatusCodes.Status429TooManyRequests);
            }

            var query = request.Query?.Trim();
            if (string.IsNullOrWhiteSpace(query) || query.Length > MaxQueryLength)
            {
                return InvalidRequest("搜索关键字长度必须为 1 到 100 个字符。");
            }

            var limit = request.Limit ?? Math.Min(20, search.MaxResults);
            if (limit < 1 || limit > search.MaxResults)
            {
                return InvalidRequest($"limit 必须为 1 到 {search.MaxResults}。");
            }

            var sources = (request.Sources is { Count: > 0 } ? request.Sources : search.AllowedSources)
                .Where(source => !string.IsNullOrWhiteSpace(source))
                .Select(source => source.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
            if (sources.Length == 0 || sources.Length > MaxSourceCount ||
                sources.Any(source => !search.AllowedSources.Contains(source, StringComparer.OrdinalIgnoreCase)))
            {
                return InvalidRequest("请求包含未允许的在线音乐来源。");
            }

            try
            {
                return Results.Ok(await search.SearchAsync(
                    new OnlineMusicSearchQuery(query, sources, limit, request.Cursor),
                    cancellationToken));
            }
            catch (OnlineMusicSearchException exception) when (exception.Failure == OnlineMusicSearchFailure.Timeout)
            {
                return Results.Json(
                    new ProblemResponse("online_music_upstream_timeout", "在线音乐来源响应超时，请稍后重试。"),
                    statusCode: StatusCodes.Status504GatewayTimeout);
            }
            catch (OnlineMusicSearchException)
            {
                return Results.Json(
                    new ProblemResponse("online_music_source_unavailable", "在线音乐服务暂时不可用。"),
                    statusCode: StatusCodes.Status503ServiceUnavailable);
            }
        });

        endpoints.MapPost("/api/online-music/tracks/{source}/{trackId}/playback", async (
            string source,
            string trackId,
            HttpContext httpContext,
            IAuthService auth,
            IOnlineMusicPlaybackService playback,
            CancellationToken cancellationToken) =>
        {
            var account = auth.Authenticate(httpContext.Request.ReadBearerToken());
            if (account is null) return Results.Unauthorized();

            try
            {
                return Results.Ok(await playback.IssueAsync(
                    account.Username,
                    source,
                    trackId,
                    cancellationToken));
            }
            catch (OnlineMusicPlaybackException exception)
            {
                return PlaybackTicketProblem(exception);
            }
        });

        endpoints.MapGet("/api/online-music/playback/{ticket}", async (
            string ticket,
            HttpContext httpContext,
            IAuthService auth,
            IOnlineMusicPlaybackService playback,
            CancellationToken cancellationToken) =>
        {
            var account = auth.Authenticate(httpContext.Request.ReadBearerToken());
            if (account is null) return Results.Unauthorized();

            try
            {
                var stream = await playback.OpenAsync(
                    account.Username,
                    ticket,
                    httpContext.Request.Headers.Range.FirstOrDefault(),
                    cancellationToken);
                return new OnlineMusicStreamResult(stream);
            }
            catch (OnlineMusicPlaybackException exception)
            {
                return PlaybackStreamProblem(exception);
            }
        });

        endpoints.MapGet("/api/online-music/tracks/{source}/{trackId}/lyrics", async (
            string source,
            string trackId,
            HttpContext httpContext,
            IAuthService auth,
            IOnlineMusicAssetService assets,
            CancellationToken cancellationToken) =>
        {
            if (auth.Authenticate(httpContext.Request.ReadBearerToken()) is null) return Results.Unauthorized();

            try
            {
                return Results.Ok(await assets.GetLyricsAsync(source, trackId, cancellationToken));
            }
            catch (OnlineMusicAssetException exception)
            {
                return AssetProblem(exception);
            }
        });

        endpoints.MapGet("/api/online-music/tracks/{source}/{trackId}/cover", async (
            string source,
            string trackId,
            HttpContext httpContext,
            IAuthService auth,
            IOnlineMusicAssetService assets,
            CancellationToken cancellationToken) =>
        {
            if (auth.Authenticate(httpContext.Request.ReadBearerToken()) is null) return Results.Unauthorized();

            try
            {
                return new OnlineMusicArtworkResult(await assets.GetArtworkAsync(
                    source,
                    trackId,
                    cancellationToken));
            }
            catch (OnlineMusicAssetException exception)
            {
                return AssetProblem(exception);
            }
        });

        return endpoints;
    }

    private static IResult InvalidRequest(string message) => Results.BadRequest(
        new ProblemResponse("online_music_invalid_request", message));

    private static IResult PlaybackTicketProblem(OnlineMusicPlaybackException exception) =>
        exception.Failure switch
        {
            OnlineMusicPlaybackFailure.InvalidTrack => Results.BadRequest(
                new ProblemResponse("online_music_invalid_request", "歌曲来源或标识无效。")),
            OnlineMusicPlaybackFailure.Timeout => Results.Json(
                new ProblemResponse("online_music_upstream_timeout", "在线音乐来源响应超时，请稍后重试。"),
                statusCode: StatusCodes.Status504GatewayTimeout),
            _ => Results.Json(
                new ProblemResponse("online_music_source_unavailable", "在线音乐服务暂时不可用。"),
                statusCode: StatusCodes.Status503ServiceUnavailable)
        };

    private static IResult PlaybackStreamProblem(OnlineMusicPlaybackException exception) =>
        exception.Failure switch
        {
            OnlineMusicPlaybackFailure.NotFound or OnlineMusicPlaybackFailure.Forbidden => Results.Json(
                new ProblemResponse("online_music_playback_not_found", "播放票据不存在。"),
                statusCode: StatusCodes.Status404NotFound),
            OnlineMusicPlaybackFailure.Expired => Results.Json(
                new ProblemResponse("online_music_playback_expired", "播放票据已过期，请重新播放。"),
                statusCode: StatusCodes.Status410Gone),
            OnlineMusicPlaybackFailure.InvalidRange => Results.Json(
                new ProblemResponse("online_music_invalid_range", "请求的音频范围无效。"),
                statusCode: StatusCodes.Status416RangeNotSatisfiable),
            OnlineMusicPlaybackFailure.Timeout => Results.Json(
                new ProblemResponse("online_music_upstream_timeout", "在线音乐来源响应超时，请稍后重试。"),
                statusCode: StatusCodes.Status504GatewayTimeout),
            _ => Results.Json(
                new ProblemResponse("online_music_source_unavailable", "在线音乐服务暂时不可用。"),
                statusCode: StatusCodes.Status502BadGateway)
        };

    private static IResult AssetProblem(OnlineMusicAssetException exception) =>
        exception.Failure switch
        {
            OnlineMusicAssetFailure.InvalidTrack => Results.BadRequest(
                new ProblemResponse("online_music_invalid_request", "歌曲来源或标识无效。")),
            OnlineMusicAssetFailure.NotFound => Results.Json(
                new ProblemResponse("online_music_asset_not_found", "该歌曲暂无可用资源。"),
                statusCode: StatusCodes.Status404NotFound),
            OnlineMusicAssetFailure.TooLarge => Results.Json(
                new ProblemResponse("online_music_asset_too_large", "在线音乐资源超过大小限制。"),
                statusCode: StatusCodes.Status502BadGateway),
            OnlineMusicAssetFailure.Timeout => Results.Json(
                new ProblemResponse("online_music_upstream_timeout", "在线音乐来源响应超时，请稍后重试。"),
                statusCode: StatusCodes.Status504GatewayTimeout),
            OnlineMusicAssetFailure.Disabled => Results.Json(
                new ProblemResponse("online_music_source_unavailable", "在线音乐服务暂时不可用。"),
                statusCode: StatusCodes.Status503ServiceUnavailable),
            _ => Results.Json(
                new ProblemResponse("online_music_source_unavailable", "在线音乐资源暂时不可用。"),
                statusCode: StatusCodes.Status502BadGateway)
        };

    private sealed class OnlineMusicArtworkResult(OnlineMusicArtwork artwork) : IResult
    {
        public async Task ExecuteAsync(HttpContext httpContext)
        {
            httpContext.Response.Headers.CacheControl = "private, max-age=3600";
            httpContext.Response.Headers.ETag = artwork.ETag;
            httpContext.Response.Headers["X-Content-Type-Options"] = "nosniff";
            if (string.Equals(
                httpContext.Request.Headers.IfNoneMatch.ToString(),
                artwork.ETag,
                StringComparison.Ordinal))
            {
                httpContext.Response.StatusCode = StatusCodes.Status304NotModified;
                return;
            }

            httpContext.Response.StatusCode = StatusCodes.Status200OK;
            httpContext.Response.ContentType = artwork.ContentType;
            httpContext.Response.ContentLength = artwork.Bytes.Length;
            await httpContext.Response.Body.WriteAsync(
                artwork.Bytes,
                httpContext.RequestAborted);
        }
    }

    private sealed class OnlineMusicStreamResult(OnlineMusicStreamResponse stream) : IResult
    {
        public async Task ExecuteAsync(HttpContext httpContext)
        {
            await using (stream)
            {
                httpContext.Response.StatusCode = stream.StatusCode;
                httpContext.Response.ContentLength = stream.ContentLength;
                httpContext.Response.ContentType = stream.ContentType;
                SetHeader(httpContext.Response, "Accept-Ranges", stream.AcceptRanges);
                SetHeader(httpContext.Response, "Content-Range", stream.ContentRange);
                SetHeader(httpContext.Response, "ETag", stream.ETag);
                await stream.Content.CopyToAsync(
                    httpContext.Response.Body,
                    httpContext.RequestAborted);
            }
        }

        private static void SetHeader(HttpResponse response, string name, string? value)
        {
            if (!string.IsNullOrWhiteSpace(value)) response.Headers[name] = value;
        }
    }
}
