param(
    [Parameter(Mandatory = $true)][string]$ServerDir,
    [Parameter(Mandatory = $true)][string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
$handler = [Net.Http.HttpClientHandler]::new()
$handler.UseProxy = $false
$http = [Net.Http.HttpClient]::new($handler)
$http.Timeout = [TimeSpan]::FromSeconds(5)
try {
    foreach ($id in @('fishr','imper')) {
        $path = "materials/panorama/images/tournaments/teams/$id.svg"
        $response = $http.GetAsync("$BaseUrl/$path").GetAwaiter().GetResult()
        try {
            if (-not $response.IsSuccessStatusCode) { throw "Asset failed: $path" }
            $bytes = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            $expected = [IO.File]::ReadAllBytes((Join-Path $ServerDir "csgo/$path"))
            if ([Convert]::ToBase64String($bytes) -ne [Convert]::ToBase64String($expected)) {
                throw "Downloaded bytes differ from the source: $path"
            }
            $head = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Head, "$BaseUrl/$path")
            $headers = $http.SendAsync($head).GetAwaiter().GetResult()
            try {
                if (-not $headers.IsSuccessStatusCode -or $headers.Content.Headers.ContentLength -ne $bytes.Length) {
                    throw "Invalid HEAD response for $path"
                }
            } finally { $headers.Dispose(); $head.Dispose() }
        } finally { $response.Dispose() }
    }
    foreach ($path in @('cfg/server.cfg','addons/sourcemod/data/sqlite/bot_tactical_experience.sq3','materials/%2e%2e/cfg/server.cfg','materials/panorama/images/tournaments/teams/nonexistent.svg')) {
        $response = $http.GetAsync("$BaseUrl/$path").GetAwaiter().GetResult()
        try { if ([int]$response.StatusCode -ne 404) { throw "Private/missing path was exposed: $path" } }
        finally { $response.Dispose() }
    }
    Write-Host 'LAN resource HTTP integration passed: original asset bytes, HEAD, private paths and missing files.'
} finally { $http.Dispose(); $handler.Dispose() }
