dotnet restore *.csproj
dotnet build *.csproj
dotnet publish *.csproj
dotnet run *.csproj

# use "-v ${PWD}:c:/api" for windows
docker run --rm -it -v ${PWD}:/api -p 5000:80 --name microsoft/dotnet:2.1-aspnetcore-runtime
