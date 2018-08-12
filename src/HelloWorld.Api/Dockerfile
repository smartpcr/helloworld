FROM microsoft/dotnet:2.1-aspnetcore-runtime AS base
WORKDIR /app
EXPOSE 50685
EXPOSE 44329

FROM microsoft/dotnet:2.1-sdk AS build
WORKDIR /src
COPY HelloWorld.Api/HelloWorld.Api.csproj HelloWorld.Api/
RUN dotnet restore HelloWorld.Api/HelloWorld.Api.csproj
COPY . .
WORKDIR /src/HelloWorld.Api
RUN dotnet build HelloWorld.Api.csproj -c Release -o /app

FROM build AS publish
RUN dotnet publish HelloWorld.Api.csproj -c Release -o /app

FROM base AS final
WORKDIR /app
COPY --from=publish /app .
ENTRYPOINT ["dotnet", "HelloWorld.Api.dll"]
