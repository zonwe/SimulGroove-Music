using System.Collections.Concurrent;
using System.Security.Cryptography;
using Microsoft.Extensions.Options;
using Music.Api.Models;

namespace Music.Api.Services.OnlineMusic;

public enum OnlineMusicPlaybackFailure
{
    Disabled,
    InvalidTrack,
    Unavailable,
    Timeout,
    NotFound,
    Expired,
    Forbidden,
    InvalidRange
}

public sealed class OnlineMusicPlaybackException(
    OnlineMusicPlaybackFailure failure,
    string message,
    Exception? innerException = null) : Exception(message, innerException)
{
    public OnlineMusicPlaybackFailure Failure { get; } = failure;
}

public interface IOnlineMusicPlaybackService
{
    Task<OnlineMusicPlaybackResponse> IssueAsync(
        string username,
        string source,
        string trackId,
        CancellationToken cancellationToken);

    Task<OnlineMusicStreamResponse> OpenAsync(
        string username,
        string ticket,
        string? range,
        CancellationToken cancellationToken);
}

public sealed class OnlineMusicPlaybackService : IOnlineMusicPlaybackService
{
    private readonly IOnlineMusicGateway _gateway;
    private readonly OnlineMusicOptions _options;
    private readonly TimeSpan _ticketLifetime;
    private readonly ConcurrentDictionary<string, PlaybackTicket> _tickets = new(StringComparer.Ordinal);
    private readonly TimeProvider _timeProvider;

    public OnlineMusicPlaybackService(
        IOnlineMusicGateway gateway,
        IOptions<OnlineMusicOptions> options,
        TimeProvider? timeProvider = null)
    {
        _gateway = gateway;
        _options = options.Value;
        _ticketLifetime = TimeSpan.FromSeconds(Math.Clamp(_options.PlaybackTicketSeconds, 60, 300));
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<OnlineMusicPlaybackResponse> IssueAsync(
        string username,
        string source,
        string trackId,
        CancellationToken cancellationToken)
    {
        if (!_options.Enabled)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Disabled, "Online music is disabled.");
        }
        source = source.Trim();
        trackId = trackId.Trim();
        if (string.IsNullOrWhiteSpace(source) || string.IsNullOrWhiteSpace(trackId) ||
            trackId.Length > 512 || !_options.AllowedSources.Contains(source, StringComparer.OrdinalIgnoreCase))
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.InvalidTrack, "Track is not allowed.");
        }

        OnlineMusicResolvedStream resolved;
        try
        {
            resolved = await _gateway.ResolveAsync(source, trackId, cancellationToken);
        }
        catch (OnlineMusicGatewayException exception) when (exception.Failure == OnlineMusicGatewayFailure.Timeout)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Timeout, "Track resolve timed out.", exception);
        }
        catch (OnlineMusicGatewayException exception)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Unavailable, "Track resolve failed.", exception);
        }

        var now = _timeProvider.GetUtcNow();
        var expiresAt = now.Add(_ticketLifetime);
        if (resolved.ExpiresAt < expiresAt) expiresAt = resolved.ExpiresAt;
        if (expiresAt <= now)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Unavailable, "Resolved stream already expired.");
        }

        RemoveExpired(now);
        var ticket = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        _tickets[ticket] = new PlaybackTicket(username, source, trackId, resolved.StreamRef, expiresAt);
        return new OnlineMusicPlaybackResponse(
            $"/api/online-music/playback/{ticket}",
            expiresAt,
            resolved.MimeType);
    }

    public async Task<OnlineMusicStreamResponse> OpenAsync(
        string username,
        string ticket,
        string? range,
        CancellationToken cancellationToken)
    {
        if (!_tickets.TryGetValue(ticket, out var playbackTicket))
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.NotFound, "Playback ticket was not found.");
        }
        var now = _timeProvider.GetUtcNow();
        if (playbackTicket.ExpiresAt <= now)
        {
            _tickets.TryRemove(ticket, out _);
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Expired, "Playback ticket expired.");
        }
        if (!string.Equals(playbackTicket.Username, username, StringComparison.Ordinal))
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Forbidden, "Playback ticket belongs to another account.");
        }

        try
        {
            return await _gateway.OpenStreamAsync(playbackTicket.StreamRef, range, cancellationToken);
        }
        catch (OnlineMusicGatewayException exception) when (exception.Failure == OnlineMusicGatewayFailure.InvalidRange)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.InvalidRange, "Online stream range is invalid.", exception);
        }
        catch (OnlineMusicGatewayException exception) when (exception.Failure == OnlineMusicGatewayFailure.Timeout)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Timeout, "Online stream timed out.", exception);
        }
        catch (OnlineMusicGatewayException exception)
        {
            throw new OnlineMusicPlaybackException(OnlineMusicPlaybackFailure.Unavailable, "Online stream failed.", exception);
        }
    }

    private void RemoveExpired(DateTimeOffset now)
    {
        foreach (var pair in _tickets)
        {
            if (pair.Value.ExpiresAt <= now) _tickets.TryRemove(pair.Key, out _);
        }
    }

    private sealed record PlaybackTicket(
        string Username,
        string Source,
        string TrackId,
        string StreamRef,
        DateTimeOffset ExpiresAt);
}
