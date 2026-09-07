namespace Music.Api.OpenApi;

public static class OpenApiDocument
{
    public static object Create() => new Dictionary<string, object>
    {
        ["openapi"] = "3.0.3",
        ["info"] = new { title = "SimulGroove Music API", version = "1.0.0" },
        ["paths"] = new Dictionary<string, object>
        {
            ["/health"] = new { get = new { summary = "Health check", responses = new Dictionary<string, object> { ["200"] = new { description = "Success" } } } },
            ["/health/ready"] = new { get = new { summary = "Dependency readiness check", responses = new Dictionary<string, object> { ["200"] = new { description = "Ready" }, ["503"] = new { description = "A required dependency is unavailable" } } } },
            ["/api/auth/login"] = new { post = new { summary = "Login", requestBody = RequestBody("LoginRequest"), responses = new Dictionary<string, object> { ["200"] = Response("AuthTokenResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse() } } },
            ["/api/auth/refresh"] = new { post = new { summary = "Rotate refresh token", requestBody = RequestBody("RefreshTokenRequest"), responses = new Dictionary<string, object> { ["200"] = Response("AuthTokenResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse() } } },
            ["/api/auth/me"] = new { get = new { summary = "Current session", security = Security(), responses = new Dictionary<string, object> { ["200"] = Response("SessionAccountResponse"), ["401"] = ErrorResponse() } } },
            ["/api/auth/logout"] = new { post = new { summary = "Logout and revoke refresh tokens", security = Security(), responses = new Dictionary<string, object> { ["204"] = new { description = "No content" }, ["401"] = ErrorResponse() } } },
            ["/api/playlists/sync"] = new { post = new { summary = "Sync playlists and liked tracks", security = Security(), requestBody = RequestBody("SyncPlaylistsRequest"), responses = new Dictionary<string, object> { ["200"] = Response("LibrarySyncResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse() } } },
            ["/api/scan-sources/"] = new
            {
                get = new { summary = "List music scan sources", security = Security(), responses = new Dictionary<string, object> { ["200"] = ArrayResponse("ScanSourceResponse"), ["401"] = ErrorResponse() } },
                post = new { summary = "Create a scheduled music scan source", security = Security(), requestBody = RequestBody("CreateScanSourceRequest"), responses = new Dictionary<string, object> { ["201"] = Response("ScanSourceResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["409"] = ErrorResponse() } }
            },
            ["/api/scan-sources/{id}"] = new
            {
                put = new { summary = "Update a music scan source", security = Security(), parameters = IdParameter(), requestBody = RequestBody("UpdateScanSourceRequest"), responses = new Dictionary<string, object> { ["200"] = Response("ScanSourceResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["409"] = ErrorResponse() } },
                delete = new { summary = "Delete a music scan source and its indexed tracks", security = Security(), parameters = IdParameter(), responses = new Dictionary<string, object> { ["204"] = new { description = "No content" }, ["401"] = ErrorResponse(), ["404"] = ErrorResponse() } }
            },
            ["/api/scan-sources/{id}/scan"] = new { post = new { summary = "Run a music scan immediately", security = Security(), parameters = IdParameter(), responses = new Dictionary<string, object> { ["200"] = Response("ScanSourceResponse"), ["401"] = ErrorResponse(), ["404"] = ErrorResponse() } } },
            ["/api/scan-sources/{id}/tracks"] = new { get = new { summary = "List tracks indexed for a scan source", security = Security(), parameters = IdAndLimitParameters(), responses = new Dictionary<string, object> { ["200"] = ArrayResponse("ScannedTrackResponse"), ["401"] = ErrorResponse() } } },
            ["/api/scan-sources/{id}/tracks/{trackId}/stream"] = new { get = new { summary = "Stream an indexed server track with Range support", security = Security(), parameters = ScannedTrackStreamParameters(), responses = new Dictionary<string, object> { ["200"] = BinaryResponse(), ["206"] = BinaryResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["416"] = ErrorResponse() } } },
            ["/api/audit-logs"] = new { get = new { summary = "Query account-scoped audit logs", security = Security(), parameters = AuditParameters(), responses = new Dictionary<string, object> { ["200"] = Response("AuditLogPageResponse"), ["401"] = ErrorResponse() } } },
            ["/api/online-music/sources"] = new { get = new { summary = "List configured online music sources", security = Security(), responses = new Dictionary<string, object> { ["200"] = Response("OnlineMusicSourcesResponse"), ["401"] = ErrorResponse() } } },
            ["/api/online-music/search"] = new { post = new { summary = "Search configured online music sources", security = Security(), requestBody = RequestBody("OnlineMusicSearchRequest"), responses = new Dictionary<string, object> { ["200"] = Response("OnlineMusicSearchResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["429"] = ErrorResponse(), ["503"] = ErrorResponse(), ["504"] = ErrorResponse() } } },
            ["/api/online-music/tracks/{source}/{trackId}/playback"] = new { post = new { summary = "Issue an account-bound online playback ticket", security = Security(), parameters = OnlineTrackParameters(), responses = new Dictionary<string, object> { ["200"] = Response("OnlineMusicPlaybackResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["503"] = ErrorResponse(), ["504"] = ErrorResponse() } } },
            ["/api/online-music/playback/{ticket}"] = new { get = new { summary = "Stream online audio with Range support", security = Security(), parameters = PlaybackTicketParameters(), responses = new Dictionary<string, object> { ["200"] = BinaryResponse(), ["206"] = BinaryResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["410"] = ErrorResponse(), ["416"] = ErrorResponse(), ["502"] = ErrorResponse(), ["504"] = ErrorResponse() } } },
            ["/api/online-music/tracks/{source}/{trackId}/lyrics"] = new { get = new { summary = "Get normalized online track lyrics", security = Security(), parameters = OnlineTrackParameters(), responses = new Dictionary<string, object> { ["200"] = Response("OnlineMusicLyricsResponse"), ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["502"] = ErrorResponse(), ["504"] = ErrorResponse() } } },
            ["/api/online-music/tracks/{source}/{trackId}/cover"] = new { get = new { summary = "Get proxied online track artwork", security = Security(), parameters = OnlineTrackParameters(), responses = new Dictionary<string, object> { ["200"] = ArtworkResponse(), ["304"] = new { description = "Not modified" }, ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["502"] = ErrorResponse(), ["504"] = ErrorResponse() } } }
            , ["/api/online-music/tracks/{source}/{trackId}/download"] = new { get = new { summary = "Download an online track with embedded metadata when supported", security = Security(), parameters = OnlineTrackParameters(), responses = new Dictionary<string, object> { ["200"] = new { description = "Audio download" }, ["400"] = ErrorResponse(), ["401"] = ErrorResponse(), ["404"] = ErrorResponse(), ["502"] = ErrorResponse(), ["504"] = ErrorResponse() } } }
        },
        ["components"] = new
        {
            securitySchemes = new { bearerAuth = new { type = "http", scheme = "bearer" } },
            schemas = new Dictionary<string, object>
            {
                ["LoginRequest"] = new { type = "object", required = new[] { "username", "password" }, properties = new { username = new { type = "string" }, password = new { type = "string", format = "password" } } },
                ["AuthTokenResponse"] = new { type = "object", properties = new { token = new { type = "string" }, refreshToken = new { type = "string" }, expiresAt = new { type = "string", format = "date-time" }, account = Ref("Account"), trackMatchSalt = new { type = "string", description = "Public per-account salt used by clients to derive a local-only track matching key." } } },
                ["RefreshTokenRequest"] = new { type = "object", required = new[] { "refreshToken" }, properties = new { refreshToken = new { type = "string" } } },
                ["Account"] = new { type = "object", properties = new { remoteId = new { type = "string" }, username = new { type = "string" }, displayName = new { type = "string" }, avatarUri = new { type = "string", nullable = true } } },
                ["SessionAccountResponse"] = new { type = "object", properties = new { account = Ref("Account") } },
                ["SyncPlaylistsRequest"] = new { type = "object", properties = new { playlists = new { type = "array", items = Ref("Playlist") }, likedTracks = new { type = "array", items = Ref("Track") } } },
                ["Playlist"] = new { type = "object", properties = new { remoteId = new { type = "string" }, name = new { type = "string" }, updatedAt = new { type = "string", format = "date-time" }, tracks = new { type = "array", items = Ref("Track") } } },
                ["PlaylistArray"] = new { type = "array", items = Ref("Playlist") },
                ["LibrarySyncResponse"] = new { type = "object", properties = new { playlists = new { type = "array", items = Ref("Playlist") }, likedTracks = new { type = "array", items = Ref("Track") } } },
                ["Track"] = new { type = "object", properties = new { uri = new { type = "string" }, title = new { type = "string" }, artist = new { type = "string" }, album = new { type = "string" }, durationMs = new { type = "integer", nullable = true }, updatedAt = new { type = "string", format = "date-time", nullable = true }, matchToken = new { type = "string", nullable = true, pattern = "^hmac-sha256:[0-9a-f]{64}$", description = "Account-scoped blind content match token; never a raw content fingerprint." } } },
                ["CreateScanSourceRequest"] = new { type = "object", required = new[] { "path" }, properties = new { path = new { type = "string", example = "F:\\Music" }, intervalMinutes = new { type = "integer", minimum = 1, maximum = 10080, @default = 60 }, enabled = new { type = "boolean", @default = true } } },
                ["UpdateScanSourceRequest"] = new { type = "object", properties = new { path = new { type = "string" }, intervalMinutes = new { type = "integer", minimum = 1, maximum = 10080 }, enabled = new { type = "boolean" } } },
                ["ScanSourceResponse"] = new { type = "object", properties = new { id = new { type = "string" }, path = new { type = "string" }, intervalMinutes = new { type = "integer" }, enabled = new { type = "boolean" }, status = new { type = "string", example = "idle" }, trackCount = new { type = "integer" }, lastScanAt = new { type = "string", format = "date-time", nullable = true }, nextScanAt = new { type = "string", format = "date-time", nullable = true }, lastError = new { type = "string", nullable = true } } },
                ["ScannedTrackResponse"] = new { type = "object", properties = new { id = new { type = "string" }, scanSourceId = new { type = "string" }, filePath = new { type = "string" }, title = new { type = "string" }, artist = new { type = "string" }, album = new { type = "string" }, extension = new { type = "string" }, fileSize = new { type = "integer", format = "int64" }, modifiedAt = new { type = "string", format = "date-time" } } },
                ["AuditLogPageResponse"] = new { type = "object", properties = new { items = new { type = "array", items = Ref("AuditLogResponse") }, total = new { type = "integer" }, page = new { type = "integer" }, pageSize = new { type = "integer" } } },
                ["AuditLogResponse"] = new { type = "object", properties = new { id = new { type = "string" }, username = new { type = "string", nullable = true }, level = new { type = "string" }, eventType = new { type = "string" }, message = new { type = "string" }, createdAt = new { type = "string", format = "date-time" }, method = new { type = "string", nullable = true }, path = new { type = "string", nullable = true }, statusCode = new { type = "integer", nullable = true }, durationMs = new { type = "integer", nullable = true }, ipAddress = new { type = "string", nullable = true }, traceId = new { type = "string", nullable = true }, details = new { type = "string", nullable = true } } },
                ["OnlineMusicSourcesResponse"] = new { type = "object", properties = new { enabled = new { type = "boolean" }, sources = new { type = "array", items = new { type = "string" } } } },
                ["OnlineMusicSearchRequest"] = new { type = "object", required = new[] { "query" }, properties = new { query = new { type = "string", minLength = 1, maxLength = 100 }, sources = new { type = "array", maxItems = 8, items = new { type = "string" } }, limit = new { type = "integer", minimum = 1, maximum = 100, @default = 20 }, cursor = new { type = "string", nullable = true } } },
                ["OnlineMusicTrackResponse"] = new { type = "object", properties = new { provider = new { type = "string" }, trackId = new { type = "string" }, title = new { type = "string" }, artists = new { type = "array", items = new { type = "string" } }, album = new { type = "string" }, durationMs = new { type = "integer", nullable = true }, artworkUrl = new { type = "string", nullable = true }, playable = new { type = "boolean" }, capabilities = new { type = "array", items = new { type = "string" } } } },
                ["OnlineMusicWarningResponse"] = new { type = "object", properties = new { provider = new { type = "string" }, code = new { type = "string" }, message = new { type = "string" } } },
                ["OnlineMusicSearchResponse"] = new { type = "object", properties = new { items = new { type = "array", items = Ref("OnlineMusicTrackResponse") }, partial = new { type = "boolean" }, warnings = new { type = "array", items = Ref("OnlineMusicWarningResponse") }, nextCursor = new { type = "string", nullable = true } } },
                ["OnlineMusicPlaybackResponse"] = new { type = "object", properties = new { playbackUrl = new { type = "string" }, expiresAt = new { type = "string", format = "date-time" }, mimeType = new { type = "string", nullable = true } } },
                ["OnlineMusicLyricsResponse"] = new { type = "object", properties = new { lyrics = new { type = "string" }, format = new { type = "string", @enum = new[] { "lrc", "text" } } } }
            }
        }
    };

    private static object[] Security() => [new { bearerAuth = Array.Empty<string>() }];
    private static Dictionary<string, string> Ref(string schema) => new() { ["$ref"] = $"#/components/schemas/{schema}" };
    private static object RequestBody(string schema) => new { required = true, content = new Dictionary<string, object> { ["application/json"] = new { schema = Ref(schema) } } };
    private static object Response(string schema) => new { description = "Success", content = new Dictionary<string, object> { ["application/json"] = new { schema = Ref(schema) } } };
    private static object ArrayResponse(string schema) => new { description = "Success", content = new Dictionary<string, object> { ["application/json"] = new { schema = new { type = "array", items = Ref(schema) } } } };
    private static object ErrorResponse() => new { description = "Request failed" };
    private static object BinaryResponse() => new { description = "Audio stream", content = new Dictionary<string, object> { ["application/octet-stream"] = new { schema = new { type = "string", format = "binary" } } } };
    private static object ArtworkResponse() => new { description = "Artwork bytes", content = new Dictionary<string, object> { ["image/jpeg"] = new { schema = new { type = "string", format = "binary" } }, ["image/png"] = new { schema = new { type = "string", format = "binary" } }, ["image/webp"] = new { schema = new { type = "string", format = "binary" } } } };
    private static object[] IdParameter() => [new { name = "id", @in = "path", required = true, schema = new { type = "string" } }];
    private static object[] IdAndLimitParameters() =>
    [
        new { name = "id", @in = "path", required = true, schema = new { type = "string" } },
        new { name = "limit", @in = "query", required = false, schema = new { type = "integer", minimum = 1, maximum = 1000, @default = 200 } }
    ];
    private static object[] ScannedTrackStreamParameters() =>
    [
        new { name = "id", @in = "path", required = true, schema = new { type = "string" } },
        new { name = "trackId", @in = "path", required = true, schema = new { type = "string" } },
        new { name = "Range", @in = "header", required = false, schema = new { type = "string", example = "bytes=0-1048575" } }
    ];
    private static object[] AuditParameters() =>
    [
        new { name = "level", @in = "query", required = false, schema = new { type = "string", @enum = new[] { "information", "warning", "error" } } },
        new { name = "eventType", @in = "query", required = false, schema = new { type = "string" } },
        new { name = "search", @in = "query", required = false, schema = new { type = "string" } },
        new { name = "from", @in = "query", required = false, schema = new { type = "string", format = "date-time" } },
        new { name = "to", @in = "query", required = false, schema = new { type = "string", format = "date-time" } },
        new { name = "page", @in = "query", required = false, schema = new { type = "integer", minimum = 1, @default = 1 } },
        new { name = "pageSize", @in = "query", required = false, schema = new { type = "integer", minimum = 1, maximum = 100, @default = 50 } }
    ];
    private static object[] OnlineTrackParameters() =>
    [
        new { name = "source", @in = "path", required = true, schema = new { type = "string" } },
        new { name = "trackId", @in = "path", required = true, schema = new { type = "string" } }
    ];
    private static object[] PlaybackTicketParameters() =>
    [
        new { name = "ticket", @in = "path", required = true, schema = new { type = "string" } },
        new { name = "Range", @in = "header", required = false, schema = new { type = "string", example = "bytes=0-1048575" } }
    ];
}
