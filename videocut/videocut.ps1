#!/usr/bin/env pwsh

Param(
    [Parameter(Mandatory=$false)]
    [Alias("i")]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string]$InputFile,

    [Alias("o")]
    [string]$OutputDir = ".\output",

    [Alias("q")]
    [int]$Crf = 30,

    [Alias("t")]
    [int]$Tile = 200,

    [Alias("w")]
    [int]$OutW = 100,

    [Alias("h")]
    [int]$OutH = 100,

    [int]$X = 10,

    [int]$Y = 10,

    [Alias("p")]
    [int]$MaxProcesses = 4
)


if (-not $InputFile) {
    $Usage = @"
Usage: videocut [param] <arg>
  -i [file]     Input file path
  -o [dir]      Output directory path
  -q [num]      CRF quality (default: 30)
  -t [num]      Square tile resolution (e.g. 200 will cut the file in 200x200 tiles)
  -w [num]      Output tile width (default: 100)
  -h [num]      Output tile height (default: 100)
  -x [num]      Number of horizontal tiles to cut (default: 10)
  -y [num]      Number of vertical tiles to cut (default: 10)
  -p [num]      Maximum number of ffmpeg processes (default: 4)
"@
    Write-Host $Usage
    exit
}

[Console]::Write("$([char]27)[?25l")
$ResolvedInput = (Resolve-Path $InputFile).Path
$InputName = [System.IO.Path]::GetFileNameWithoutExtension($ResolvedInput)
$FinalOutDir = New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir $InputName)
$FfmpegPath = (Get-Command ffmpeg).Source

$HorTiles = $X - 1; $VerTiles = $Y - 1
$Matrix = @{}; $ProcessMatrix = @{}
$script:DoneCount = 0; $StartTime = Get-Date
$TotalTiles = ($HorTiles + 1) * ($VerTiles + 1)

function Init-Matrix {
    for ($i=0; $i -le $VerTiles; $i++) {
        for ($j=0; $j -le $HorTiles; $j++) { $Matrix["$i,$j"] = 37 }
    }
}

function Render-Matrix {
    $LinesToMove = $VerTiles + 3
    [Console]::Write("$([char]27)[$($LinesToMove)A")
    
    $Output = New-Object System.Text.StringBuilder
    for ($i = 0; $i -le $VerTiles; $i++) {
        [void]$Output.Append("$([char]27)[2K`r") 
        for ($j = 0; $j -le $HorTiles; $j++) {
            $Color = $Matrix["$i,$j"]
            [void]$Output.Append("$([char]27)[$($Color)m■ $([char]27)[0m")
        }
        [void]$Output.Append("`n")
    }
    
    $Elapsed = (Get-Date) - $StartTime
    $TitleInfo = "Rendering: $($script:DoneCount)/$TotalTiles"
    
    if ($script:DoneCount -gt 0) {
        $SecondsPerTile = $Elapsed.TotalSeconds / $script:DoneCount
        $RemainingSeconds = ($TotalTiles - $script:DoneCount) * $SecondsPerTile
        $ETA = [TimeSpan]::FromSeconds($RemainingSeconds)
        $TitleInfo += " | ETA: $($ETA.ToString('hh\:mm\:ss'))"
    }
    
    $Host.UI.RawUI.WindowTitle = $TitleInfo
    [void]$Output.Append("`n$([char]27)[2K`r$($script:DoneCount)/$TotalTiles`n")
    [Console]::Write($Output.ToString())
}

function Update-Status {
    foreach ($Key in $ProcessMatrix.Keys) {
        if ($Matrix[$Key] -eq 32 -or $Matrix[$Key] -eq 31) { continue }
        $Proc = $ProcessMatrix[$Key]
        if ($null -ne $Proc) {
            try {
                if ($Proc.HasExited) {
                    $Matrix[$Key] = if ($Proc.ExitCode -eq 0) { 32 } else { 31 }
                    $script:DoneCount++
                }
            } catch {
                $Matrix[$Key] = 31
                $script:DoneCount++
            }
        }
    }
}

try {
    #Clear-Host
    Init-Matrix
    for ($i=0; $i -le ($VerTiles + 2); $i++) { Write-Host "" }
    Render-Matrix

    for ($curY=0; $curY -le $VerTiles; $curY++) {
        for ($curX=0; $curX -le $HorTiles; $curX++) {
            
            $OutPath = Join-Path $FinalOutDir.FullName "tile_${curY}_${curX}.webm"
            $VFilter = "crop=${Tile}:${Tile}:$($curX*$Tile):$($curY*$Tile),scale=${OutW}:${OutH}"
            $CommandLine = "-y -i `"$ResolvedInput`" -an -v quiet -vf `"$VFilter`" -c:v libvpx-vp9 -pix_fmt yuva420p -crf $Crf -b:v 0 `"$OutPath`" >nul 2>&1"

            $Proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c ffmpeg $CommandLine" -NoNewWindow -PassThru
            
            $ProcessMatrix["$curY,$curX"] = $Proc
            $Matrix["$curY,$curX"] = 34

            while (@(Get-Process -Id ($ProcessMatrix.Values.Id) -ErrorAction SilentlyContinue).Count -ge $MaxProcesses) {
                Start-Sleep -Milliseconds 200
                Update-Status
                Render-Matrix
            }
            Update-Status
            Render-Matrix
        }
    }

    while ($script:DoneCount -lt $TotalTiles) {
        Start-Sleep -Milliseconds 500
        Update-Status
        Render-Matrix
    }

    $Duration = (Get-Date) - $StartTime
    $SizeByte = (Get-ChildItem $FinalOutDir -Recurse | Measure-Object -Property Length -Sum).Sum
    $TotalSize = if ($SizeByte -ge 1GB) { "$([Math]::Round($SizeByte/1GB, 2))G" } elseif ($SizeByte -ge 1MB) { "$([Math]::Round($SizeByte/1MB, 1))M" } else { "$([Math]::Round($SizeByte/1KB, 0))K" }

    [System.Console]::Beep(440, 500)
    Write-Host "`n$([char]27)[30;42m DONE $([char]27)[0m"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ("Time elapsed:  {0:d2}:{1:d2}:{2:d2}" -f [int]$Duration.TotalHours, $Duration.Minutes, $Duration.Seconds)
    Write-Host ("Total tiles:   {0}" -f $TotalTiles)
    Write-Host ("Output size:   {0}" -f $TotalSize)
    Write-Host ("Directory:     {0}" -f $FinalOutDir.FullName)
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

} 
finally {
    [Console]::Write("$([char]27)[?25h")
    $Host.UI.RawUI.WindowTitle = "PowerShell"

    if ($null -ne $ProcessMatrix) {
        foreach ($Proc in $ProcessMatrix.Values) {
            if ($null -ne $Proc -and -not $Proc.HasExited) {
                Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
