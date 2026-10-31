FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY PlaceHub.slnx ./
COPY src/PlaceHub.Core/PlaceHub.Core.csproj src/PlaceHub.Core/
COPY src/PlaceHub.Web/PlaceHub.Web.csproj src/PlaceHub.Web/
RUN dotnet restore src/PlaceHub.Web/PlaceHub.Web.csproj
COPY src/ src/
RUN dotnet publish src/PlaceHub.Web/PlaceHub.Web.csproj -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app ./
USER app
ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "PlaceHub.Web.dll"]
