<#
  .SYNOPSIS
  Generates the data behind the Azure Local releases site: a JSON data file, an RSS feed and a JSON Feed.

  .DESCRIPTION
  Retrieves releases using Get-AzureLocalRelease and writes:
    <OutputPath>\data\releases.json  Releases and release trains (consumed by the site)
    <OutputPath>\feed.xml            RSS 2.0 feed
    <OutputPath>\feed.json           JSON Feed 1.1
    <LegacyJsonPath>                 Plain array of releases (kept for consumers of the original raw JSON file)
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory=$false)]
  [String]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\site'),

  [Parameter(Mandatory=$false)]
  [String]$LegacyJsonPath = (Join-Path -Path $PSScriptRoot -ChildPath '..\json\azure-local-releases.json'),

  [Parameter(Mandatory=$false)]
  [String]$SiteUrl = $(if ($env:SITE_URL) { $env:SITE_URL } elseif ($env:GITHUB_REPOSITORY) { 'https://{0}.github.io/{1}/' -f ($env:GITHUB_REPOSITORY -split '/')[0].ToLower(), ($env:GITHUB_REPOSITORY -split '/')[1] } else { 'https://erikgraa.github.io/azure-local-releases/' }),

  [Parameter(Mandatory=$false)]
  [Int]$FeedItemCount = 30,

  # Guards against publishing an empty or partially parsed site if Microsoft's documentation changes format
  [Parameter(Mandatory=$false)]
  [Int]$MinimumReleaseCount = 20
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'Get-AzureLocalRelease.ps1')

$sourceUrl = 'https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2'
$SiteUrl = $SiteUrl.TrimEnd('/') + '/'

$releases = @(Get-AzureLocalRelease)

if ($releases.Count -lt $MinimumReleaseCount) {
  throw ('Only {0} releases were parsed (expected at least {1}), the documentation format may have changed' -f $releases.Count, $MinimumReleaseCount)
}

if (-not ($releases | Where-Object { $_.supported })) {
  throw 'No supported releases were found, the documentation format may have changed'
}

$utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false

function Write-TextFile {
  param ([String]$Path, [String]$Content)

  $directory = Split-Path -Path $Path -Parent

  if (-not (Test-Path -Path $directory -PathType Container)) {
    $null = New-Item -Path $directory -ItemType Directory -Force
  }

  [System.IO.File]::WriteAllText($Path, $Content, $utf8)
}

$generatedAt = [DateTime]::UtcNow

$newestFirst = @($releases | Sort-Object -Property @{ Expression = { [DateTime]$_.availabilityDate }; Descending = $true }, @{ Expression = { [Version]$_.version }; Descending = $true })

$trains = @($releases | Group-Object -Property releaseTrain | Sort-Object -Property Name -Descending | ForEach-Object {
  $group = @($_.Group)

  [Ordered]@{
    'releaseTrain' = $_.Name
    'osVersions' = @($group.osVersion | Sort-Object -Unique)
    'firstAvailabilityDate' = ($group.firstAvailabilityDate | Sort-Object | Select-Object -First 1)
    'endOfSupportDate' = ($group.endOfSupportDate | Sort-Object | Select-Object -Last 1)
    'supported' = [Bool]($group | Where-Object { $_.supported })
    'versions' = @($group.version)
  }
})

$data = [Ordered]@{
  'generatedAt' = $generatedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
  'source' = $sourceUrl
  'supportPolicy' = [Ordered]@{
    'days' = 180
    'description' = 'Each Azure Local release is supported for six months (180 days) after it first became available. endOfSupportDate is derived from firstAvailabilityDate.'
  }
  'newDeployments' = @($releases | Where-Object { $_.newDeployments } | ForEach-Object { $_.version })
  'trains' = $trains
  'releases' = $newestFirst
}

Write-TextFile -Path (Join-Path $OutputPath 'data\releases.json') -Content (($data | ConvertTo-Json -Depth 6) + "`n")
Write-TextFile -Path $LegacyJsonPath -Content (($releases | ConvertTo-Json -Depth 6) + "`n")

$feedItems = @($newestFirst | Select-Object -First $FeedItemCount | ForEach-Object {
  $summary = ('Azure Local {0} (OS build {1}, {2}) became available on {3}. End of support: {4}.' -f $_.version, $_.osBuild, $_.osVersion, $_.availabilityDate, $_.endOfSupportDate)

  if ($_.newDeployments) {
    $summary += ' Use this build for new deployments.'
  }

  [PSCustomObject]@{
    'id' = ('azure-local-{0}' -f $_.version)
    'title' = ('Azure Local {0} released' -f $_.version)
    'url' = $_.urls.news
    'summary' = $summary
    'date' = [DateTime]::ParseExact($_.availabilityDate, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
    'tags' = @($_.releaseTrain, $_.osVersion)
  }
})

$escape = { param ($Text) [System.Security.SecurityElement]::Escape($Text) }

$rss = New-Object -TypeName System.Text.StringBuilder
$null = $rss.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
$null = $rss.AppendLine('<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">')
$null = $rss.AppendLine('  <channel>')
$null = $rss.AppendLine('    <title>Azure Local releases</title>')
$null = $rss.AppendLine(('    <link>{0}</link>' -f (& $escape $SiteUrl)))
$null = $rss.AppendLine('    <description>New Azure Local releases and when they reach end of support.</description>')
$null = $rss.AppendLine('    <language>en</language>')
$null = $rss.AppendLine(('    <lastBuildDate>{0}</lastBuildDate>' -f $generatedAt.ToString('r')))
$null = $rss.AppendLine(('    <atom:link href="{0}" rel="self" type="application/rss+xml" />' -f (& $escape ($SiteUrl + 'feed.xml'))))

foreach ($_item in $feedItems) {
  $null = $rss.AppendLine('    <item>')
  $null = $rss.AppendLine(('      <title>{0}</title>' -f (& $escape $_item.title)))
  $null = $rss.AppendLine(('      <link>{0}</link>' -f (& $escape $_item.url)))
  $null = $rss.AppendLine(('      <guid isPermaLink="false">{0}</guid>' -f (& $escape $_item.id)))
  $null = $rss.AppendLine(('      <pubDate>{0}</pubDate>' -f $_item.date.ToString('r')))
  $null = $rss.AppendLine(('      <description>{0}</description>' -f (& $escape $_item.summary)))

  foreach ($_tag in $_item.tags) {
    $null = $rss.AppendLine(('      <category>{0}</category>' -f (& $escape $_tag)))
  }

  $null = $rss.AppendLine('    </item>')
}

$null = $rss.AppendLine('  </channel>')
$null = $rss.AppendLine('</rss>')

Write-TextFile -Path (Join-Path $OutputPath 'feed.xml') -Content $rss.ToString()

$jsonFeed = [Ordered]@{
  'version' = 'https://jsonfeed.org/version/1.1'
  'title' = 'Azure Local releases'
  'home_page_url' = $SiteUrl
  'feed_url' = ($SiteUrl + 'feed.json')
  'description' = 'New Azure Local releases and when they reach end of support.'
  'language' = 'en'
  'items' = @($feedItems | ForEach-Object {
    [Ordered]@{
      'id' = $_.id
      'url' = $_.url
      'title' = $_.title
      'content_text' = $_.summary
      'date_published' = $_.date.ToString('yyyy-MM-ddTHH:mm:ssZ')
      'tags' = $_.tags
    }
  })
}

Write-TextFile -Path (Join-Path $OutputPath 'feed.json') -Content (($jsonFeed | ConvertTo-Json -Depth 6) + "`n")

Write-Host ('Generated {0} releases ({1} supported) in {2}' -f $releases.Count, @($releases | Where-Object { $_.supported }).Count, (Resolve-Path -Path $OutputPath))
