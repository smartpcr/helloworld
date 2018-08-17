FROM microsoft/dotnet:2.1-aspnetcore-runtime

WORKDIR /api
COPY bin/Debug/netcoreapp2.1/publish .

ENTRYPOINT ["dotnet", "generator-api.dll"]