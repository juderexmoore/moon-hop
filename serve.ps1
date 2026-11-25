# Moon Hop launcher.
# Serves the game from this folder at http://localhost:8765/ and keeps the
# leaderboard in scores.json right here, so it survives every new build.
# Close this window when you're done playing.
param(
  [int]$Port = 8765,
  [switch]$NoBrowser
)

$root = (Resolve-Path $PSScriptRoot).Path
$url = "http://localhost:$Port/"
$utf8 = New-Object System.Text.UTF8Encoding($false)

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
try {
  $listener.Start()
} catch {
  # Already running (or the port is busy): just open the game.
  if (-not $NoBrowser) { Start-Process $url }
  exit
}

Write-Host ""
Write-Host "  MOON HOP is running at $url"
Write-Host "  Scores, levels and characters are saved in the game folder."
Write-Host "  Close this window when you're done playing."
Write-Host ""
if (-not $NoBrowser) { Start-Process $url }

$types = @{
  '.html' = 'text/html; charset=utf-8'; '.js' = 'text/javascript'; '.css' = 'text/css'
  '.json' = 'application/json'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'
  '.svg' = 'image/svg+xml'; '.ico' = 'image/x-icon'
}

function Send-Reply($res, [int]$code, [string]$type, [byte[]]$bytes) {
  $res.StatusCode = $code
  $res.ContentType = $type
  $res.Headers['Cache-Control'] = 'no-store'
  $res.ContentLength64 = $bytes.Length
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.OutputStream.Close()
}

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($req.Url.AbsolutePath)

    # /api/scores  -> scores.json  (the leaderboard)
    # /api/sandbox -> sandbox.json (your own levels and characters)
    if ($path -match '^/api/(scores|sandbox)$') {
      $key = $Matches[1]
      $dataFile = Join-Path $root "$key.json"
      if ($req.HttpMethod -eq 'POST') {
        $reader = New-Object System.IO.StreamReader($req.InputStream, $utf8)
        $body = $reader.ReadToEnd()
        $null = $body | ConvertFrom-Json            # refuse anything that isn't valid JSON
        if ($key -eq 'scores' -and -not $body.TrimStart().StartsWith('[')) { throw 'Scores must be a list' }
        if ($key -eq 'sandbox' -and -not $body.TrimStart().StartsWith('{')) { throw 'Sandbox must be an object' }
        [System.IO.File]::WriteAllText($dataFile, $body, $utf8)
        Send-Reply $res 200 'application/json' $utf8.GetBytes('{"ok":true}')
      } else {
        $json = if ($key -eq 'scores') { '[]' } else { 'null' }
        if (Test-Path -LiteralPath $dataFile) { $json = [System.IO.File]::ReadAllText($dataFile, $utf8) }
        Send-Reply $res 200 'application/json' $utf8.GetBytes($json)
      }
      continue
    }

    if ($path -eq '/') { $path = '/index.html' }
    $full = [System.IO.Path]::GetFullPath((Join-Path $root $path.TrimStart('/')))
    $inside = $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
    if ($inside -and (Test-Path -LiteralPath $full -PathType Leaf)) {
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $type = 'application/octet-stream'
      if ($types.ContainsKey($ext)) { $type = $types[$ext] }
      Send-Reply $res 200 $type ([System.IO.File]::ReadAllBytes($full))
    } else {
      Send-Reply $res 404 'text/plain' $utf8.GetBytes('Not found')
    }
  } catch {
    try { Send-Reply $res 500 'text/plain' $utf8.GetBytes('Error') } catch { }
  }
}
