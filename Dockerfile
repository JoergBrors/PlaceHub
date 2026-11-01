FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY PlaceHub.slnx ./
COPY src/PlaceHub.Core/PlaceHub.Core.csproj src/PlaceHub.Core/
COPY src/PlaceHub.Web/PlaceHub.Web.csproj src/PlaceHub.Web/
RUN dotnet restore src/PlaceHub.Web/PlaceHub.Web.csproj
COPY src/ src/
# Publish must restore itself: with --no-restore the framework static assets (_framework/blazor.web.js) are missing and Blazor stays non-interactive.
RUN dotnet publish src/PlaceHub.Web/PlaceHub.Web.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
# The aspnet base image has no HTTP client; the container healthcheck needs one (curl only, no recommended packages).
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app ./
USER app
ENV ASPNETCORE_HTTPS_PORTS=8443
EXPOSE 8443
ENTRYPOINT ["dotnet", "PlaceHub.Web.dll"]
