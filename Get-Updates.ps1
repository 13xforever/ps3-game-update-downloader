#!/bin/pwsh
# How to install PowerShell: https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell

param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string] $ProductCode,
    [string] $OutputPath = '.\game_update_pkgs'
)

if ($ProductCode -notmatch '^[A-Z]{4}[0-9]{5}$')
{
    throw "Invalid product code $ProductCode"
}

$ProductCode = $ProductCode.Trim().ToUpperInvariant()
$metaUrl = "https://a0.ww.np.dl.playstation.net/tpl/np/$ProductCode/$ProductCode-ver.xml"
try
{
    $response = Invoke-WebRequest -Uri $metaUrl -SkipCertificateCheck
}
catch [Microsoft.PowerShell.Commands.HttpResponseException]
{
    if ([int]$_.Exception.Response.StatusCode -eq 403)
    {
        Write-Verbose "No update information for product code $ProductCode"
        exit 0
    }
    else
    {
        Write-Host $_
        exit -1
    }
}

if ($response.Content.Length -eq 0)
{
    Write-Verbose "No updates available for product code $ProductCode"
    exit 0
}

$contentBytes = $response.RawContentStream.ToArray()
$updateMeta = [xml][System.Text.Encoding]::UTF8.GetString($contentBytes)

$packageList = @($updateMeta.titlepatch.tag.package)
$title = ""
$totalSize = 0L
foreach ($p in $packageList)
{
    $totalSize += [int]$p.size
    if (-not [string]::IsNullOrEmpty($p.paramsfo.TITLE))
    {
        $title = $p.paramsfo.TITLE
    }
}
if ($title -eq "")
{
    $title = "[$ProductCode]"
}
else
{
    $invalidChars = @([System.IO.Path]::GetInvalidFileNameChars() + [System.IO.Path]::GetInvalidPathChars() + @('™', '®') | Sort-Object -Unique)
    $pchars = $title.ToCharArray()
    $title = ""
    foreach ($c in $pchars)
    {
        if ($invalidChars -notcontains $c)
        {
            $title += $c
        }
    }
    $title = $title.Replace('(TM)', '').Replace('(R)', '')
    $title = "$title [$ProductCode]"
}
$outDir = Join-Path $OutputPath $ProductCode
if (-not (Test-Path -LiteralPath $outDir))
{
    New-Item -Path $outDir -ItemType Directory
}

Write-Verbose 'Saving update meta xml...'
Set-Content -LiteralPath "$outDir\$ProductCode-ver.xml" -Value $contentBytes -AsByteStream

Write-Verbose 'Saving update PKGs...'
$downloaded = 0L
$oldProgressPreference = $global:progressPreference
foreach ($p in $packageList)
{
    $activity = "Downloading update v$($p.version.TrimStart('0'))"
    Write-Progress -Id 0 -Activity $activity -PercentComplete ($downloaded * 100 / $totalSize)
    $url = [uri]$p.url
    $pkgPath = Join-Path $outDir (Split-Path $url -Leaf)
    Invoke-WebRequest -Uri $url -OutFile $pkgPath
    $downloaded += $p.size
}
$global:progressPreference = $oldProgressPreference
Write-Progress -Id 0 -Activity $activity -Completed
