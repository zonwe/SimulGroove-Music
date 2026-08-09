# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY backend/NuGet.Config backend/NuGet.Config
COPY backend/Music.Api/Music.Api.csproj backend/Music.Api/Music.Api.csproj
RUN dotnet restore backend/Music.Api/Music.Api.csproj \
    --configfile backend/NuGet.Config

COPY backend/Music.Api/ backend/Music.Api/
RUN dotnet publish backend/Music.Api/Music.Api.csproj \
    --configuration Release \
    --no-restore \
    --output /app/publish \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
RUN apt-get update \
    && apt-get install --yes --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system music-api \
    && useradd --system --gid music-api --create-home music-api \
    && mkdir --parents /data /home/music-api/.aspnet/DataProtection-Keys \
    && chown --recursive music-api:music-api /data /home/music-api

WORKDIR /app
COPY --from=build --chown=music-api:music-api /app/publish/ .

ENV ASPNETCORE_URLS=http://+:8080 \
    Database__Path=/data/music.db

USER music-api
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl --fail --silent --show-error http://127.0.0.1:8080/health/ready || exit 1

ENTRYPOINT ["dotnet", "Music.Api.dll"]
