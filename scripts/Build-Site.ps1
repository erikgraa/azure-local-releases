<#
  .SYNOPSIS
  Generates the data behind the Azure Local EOL site: JSON data, RSS and JSON feeds and ICS calendars.

  .DESCRIPTION
  Retrieves releases using Get-AzureLocalRelease and writes:
    <OutputPath>/data/releases.json         Releases and release trains (consumed by the site)
    <OutputPath>/feed.xml                   RSS 2.0 feed
    <OutputPath>/feed.json                  JSON Feed 1.1
    <OutputPath>/calendar.ics               End of support calendar, one all-day event per release
    <OutputPath>/calendar-reminders.ics     The same calendar with reminders 30 and 7 days before
    <LegacyJsonPath>                        Plain array of releases (kept for consumers of the original raw JSON file)

  Nothing is written if the retrieved content is identical to what is already on disk (the generatedAt timestamp is
  ignored in the comparison), so a scheduled run leaves no trace when nothing changed.

  Nothing is written either if anything goes wrong. Everything is generated in a temporary directory and validated by
  Test-SiteOutput.ps1 (including a comparison with the previously published data) before any file is published, and
  files are then replaced atomically. On failure the script throws, leaving all existing files untouched.

  When running in GitHub Actions the result is exposed as the step outputs "changed" (true/false) and, on failure,
  "error" (the reason).
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory=$false)]
  [String]$OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../site'),

  [Parameter(Mandatory=$false)]
  [String]$LegacyJsonPath = (Join-Path -Path $PSScriptRoot -ChildPath '../json/azure-local-releases.json'),

  # Defaults to SITE_URL, then the custom domain in <OutputPath>/CNAME, then https://<owner>.github.io/<repo>/
  [Parameter(Mandatory=$false)]
  [String]$SiteUrl,

  [Parameter(Mandatory=$false)]
  [Int]$FeedItemCount = 30,

  # Guards against publishing an empty or partially parsed site if Microsoft's documentation changes format
  [Parameter(Mandatory=$false)]
  [Int]$MinimumReleaseCount = 20,

  # Use a JSON array of releases (the format of the legacy JSON file) instead of retrieving them from Microsoft. Used by the tests.
  [Parameter(Mandatory=$false)]
  [String]$SourceJsonPath,

  # Write the files even if the content did not change, for instance after changing the site URL
  [Parameter(Mandatory=$false)]
  [Switch]$Force
)

$ErrorActionPreference = 'Stop'

$setOutput = {
  param ([String]$Name, [String]$Value)

  Write-Host ('{0}={1}' -f $Name, $Value)

  if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value ('{0}={1}' -f $Name, ($Value -replace '[\r\n]+', ' '))
  }
}

$staging = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('azure-local-site-{0}' -f [Guid]::NewGuid().ToString('N'))

try {
  . (Join-Path -Path $PSScriptRoot -ChildPath 'Get-AzureLocalRelease.ps1')

  $sourceUrl = 'https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2'

  # Event UIDs must stay the same for as long as the calendar exists, so they are independent of the site URL.
  # This is the original site domain, kept on purpose: changing it would make subscribed calendars duplicate every event.
  $uidDomain = 'releases.azurelocal.graa.dev'

  if (-not $SiteUrl) {
    $cnamePath = Join-Path -Path $OutputPath -ChildPath 'CNAME'

    if ($env:SITE_URL) {
      $SiteUrl = $env:SITE_URL
    }
    elseif ((Test-Path -Path $cnamePath -PathType Leaf) -and (Get-Content -Path $cnamePath -Raw).Trim()) {
      $SiteUrl = 'https://{0}/' -f (Get-Content -Path $cnamePath -Raw).Trim()
    }
    elseif ($env:GITHUB_REPOSITORY) {
      $SiteUrl = 'https://{0}.github.io/{1}/' -f ($env:GITHUB_REPOSITORY -split '/')[0].ToLower(), ($env:GITHUB_REPOSITORY -split '/')[1]
    }
    else {
      $SiteUrl = 'https://erikgraa.github.io/azure-local-releases/'
    }
  }

  $SiteUrl = $SiteUrl.TrimEnd('/') + '/'
  $dataPath = Join-Path -Path $OutputPath -ChildPath 'data/releases.json'

  if ($SourceJsonPath) {
    $releases = @(Get-Content -Path $SourceJsonPath -Raw | ConvertFrom-Json -Depth 10 | Where-Object { $null -ne $_ })

    # ConvertFrom-Json turns ISO dates into DateTime, turn them back into the strings the cmdlet returns
    foreach ($_release in $releases) {
      foreach ($_property in 'availabilityDate', 'firstAvailabilityDate', 'endOfSupportDate') {
        if ($_release.$_property -is [DateTime]) {
          $_release.$_property = $_release.$_property.ToString('yyyy-MM-dd')
        }
      }
    }
  }
  else {
    $releases = @(Get-AzureLocalRelease | Where-Object { $null -ne $_ })
  }

  if ($releases.Count -eq 0) {
    throw 'No releases were retrieved, the documentation format may have changed'
  }

  # Dates and versions drive the sorting and the generated files, so reject unusable values with a clear message first
  $isDay = { param ($Value) $parsed = [DateTime]::MinValue; [DateTime]::TryParseExact([String]$Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed) }

  $unusable = @($releases | Where-Object {
    [String]$_.version -notmatch '^\d+\.\d{4}\.\d+\.\d+$' -or
    -not (& $isDay $_.availabilityDate) -or -not (& $isDay $_.firstAvailabilityDate) -or -not (& $isDay $_.endOfSupportDate)
  })

  if ($unusable.Count -gt 0) {
    throw ('{0} of {1} releases have a missing or invalid version or date (for instance {2}), the documentation format may have changed' -f $unusable.Count, $releases.Count, $(if ($unusable[0].version) { $unusable[0].version } else { '(no version)' }))
  }

  $previous = $null

  if (Test-Path -Path $dataPath -PathType Leaf) {
    try {
      $previous = Get-Content -Path $dataPath -Raw | ConvertFrom-Json
    }
    catch {
      Write-Warning ('Existing data at {0} could not be read and is not used as a baseline: {1}' -f $dataPath, $_)
    }
  }

  if ($null -ne $previous) {
    # Feature highlights are best effort. Keep what was published rather than dropping it if the What's new article could not be parsed this time.
    $previousFeatures = @{}

    foreach ($_previousRelease in @($previous.releases)) {
      $published = @($_previousRelease.features | Where-Object { $null -ne $_ })

      if ($published.Count -gt 0) {
        $previousFeatures[[String]$_previousRelease.version] = $published
      }
    }

    foreach ($_release in $releases) {
      if (@($_release.features | Where-Object { $null -ne $_ }).Count -eq 0 -and $previousFeatures.ContainsKey([String]$_release.version)) {
        $_release.features = $previousFeatures[[String]$_release.version]
      }
    }
  }

  $generatedAt = [DateTime]::UtcNow
  $invariant = [Globalization.CultureInfo]::InvariantCulture

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

  $dataJson = ($data | ConvertTo-Json -Depth 8) + "`n"

  # Compare the content ignoring the generatedAt timestamp, which changes on every run
  $withoutTimestamp = { param ([String]$Text) ($Text -replace "`r`n", "`n") -replace '(?m)^\s*"generatedAt":.*\n', '' }

  $feedJsonPath = Join-Path -Path $OutputPath -ChildPath 'feed.json'

  # The feeds contain absolute URLs, so they also need regenerating when the site URL changes (for instance a new custom domain)
  $siteUrlChanged = $true

  if (Test-Path -Path $feedJsonPath -PathType Leaf) {
    try {
      $siteUrlChanged = (Get-Content -Path $feedJsonPath -Raw | ConvertFrom-Json).home_page_url -ne $SiteUrl
    }
    catch {
      $siteUrlChanged = $true
    }
  }

  $outputsMissing = @('feed.xml', 'feed.json', 'calendar.ics', 'calendar-reminders.ics') | Where-Object { -not (Test-Path -Path (Join-Path -Path $OutputPath -ChildPath $_) -PathType Leaf) }

  if (-not $Force -and -not $siteUrlChanged -and -not $outputsMissing -and (Test-Path -Path $dataPath -PathType Leaf) -and ((& $withoutTimestamp (Get-Content -Path $dataPath -Raw)) -ceq (& $withoutTimestamp $dataJson))) {
    Write-Host ('No changes in {0} releases ({1} supported), nothing written' -f $releases.Count, @($releases | Where-Object { $_.supported }).Count)
    & $setOutput 'changed' 'false'
    return
  }

  # RSS and JSON Feed
  $feedItems = @($newestFirst | Select-Object -First $FeedItemCount | ForEach-Object {
    $summary = ('Azure Local {0} (OS build {1}, {2}) became available on {3}. End of support: {4}.' -f $_.version, $_.osBuild, $_.osVersion, $_.availabilityDate, $_.endOfSupportDate)

    if ($_.newDeployments) {
      $summary += ' Use this build for new deployments.'
    }

    if (@($_.features).Count -gt 0) {
      $summary += ' Highlights: {0}.' -f ((@($_.features) | Select-Object -First 3 | ForEach-Object { $_.title }) -join '; ')
    }

    [PSCustomObject]@{
      'id' = ('azure-local-{0}' -f $_.version)
      'title' = ('Azure Local {0} released' -f $_.version)
      'url' = $_.urls.news
      'summary' = $summary
      'date' = [DateTime]::ParseExact($_.availabilityDate, 'yyyy-MM-dd', $invariant, [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal)
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

  # ICS calendars (RFC 5545)
  $escapeIcs = { param ([String]$Text) (($Text -replace '\\', '\\') -replace '([;,])', '\$1') -replace "\r?\n", '\n' }

  # Content lines are limited to 75 octets and are continued on the next line, starting with a space. Never split a character.
  $foldIcs = {
    param ([String]$Line)

    $out = New-Object -TypeName System.Text.StringBuilder
    $octets = 0

    foreach ($rune in $Line.EnumerateRunes()) {
      $size = $rune.Utf8SequenceLength

      if ($octets + $size -gt 75) {
        $null = $out.Append("`r`n ")
        $octets = 1
      }

      $null = $out.Append($rune.ToString())
      $octets += $size
    }

    $out.ToString()
  }

  # A release is identified by its major version and train (12.2610) rather than its build, which changes when a later build supersedes it.
  # The few trains with several separate releases (10.2411.0, 10.2411.1, ...) are told apart by the release (and, if needed, the build).
  $trainKey = { param ($Release) '{0}.{1}' -f ([String]$Release.version).Split('.')[0], $Release.releaseTrain }
  $releaseKey = { param ($Release) '{0}.{1}' -f ([String]$Release.version).Split('.')[0], $Release.releaseShortened }

  $trainCount = @{}
  $releaseCount = @{}

  foreach ($_release in $releases) {
    $trainCount[(& $trainKey $_release)] += 1
    $releaseCount[(& $releaseKey $_release)] += 1
  }

  $eventKey = {
    param ($Release)

    if ($trainCount[(& $trainKey $Release)] -le 1) { return (& $trainKey $Release) }
    if ($releaseCount[(& $releaseKey $Release)] -le 1) { return (& $releaseKey $Release) }

    [String]$Release.version
  }

  $stamp = $generatedAt.ToString('yyyyMMddTHHmmssZ')

  $newCalendar = {
    param ([Bool]$Reminders)

    $name = if ($Reminders) { 'Azure Local end of support (with reminders)' } else { 'Azure Local end of support' }
    $lines = New-Object -TypeName System.Collections.Generic.List[String]

    foreach ($line in @(
      'BEGIN:VCALENDAR'
      'VERSION:2.0'
      'PRODID:-//erikgraa//Azure Local EOL//EN'
      'CALSCALE:GREGORIAN'
      'METHOD:PUBLISH'
      ('NAME:{0}' -f (& $escapeIcs $name))
      ('X-WR-CALNAME:{0}' -f (& $escapeIcs $name))
      ('DESCRIPTION:{0}' -f (& $escapeIcs ('When each Azure Local release reaches end of support. Updated daily from {0}' -f $SiteUrl)))
      ('X-WR-CALDESC:{0}' -f (& $escapeIcs ('When each Azure Local release reaches end of support. Updated daily from {0}' -f $SiteUrl)))
      'REFRESH-INTERVAL;VALUE=DURATION:P1D'
      'X-PUBLISHED-TTL:P1D'
    )) { $lines.Add($line) }

    foreach ($_release in ($releases | Sort-Object -Property endOfSupportDate, version)) {
      $key = & $eventKey $_release
      $end = [DateTime]::ParseExact($_release.endOfSupportDate, 'yyyy-MM-dd', $invariant)
      $title = 'Azure Local {0}' -f $key

      $description = '{0} ({1}) reaches end of support. Each release is supported for six months after it first became available ({2}). Latest build: {3} (OS build {4}).' -f $title, $_release.osVersion, $_release.firstAvailabilityDate, $_release.version, $_release.osBuild

      foreach ($line in @(
        'BEGIN:VEVENT'
        ('UID:azure-local-{0}-eos@{1}' -f $key, $uidDomain)
        ('DTSTAMP:{0}' -f $stamp)
        ('LAST-MODIFIED:{0}' -f $stamp)
        ('DTSTART;VALUE=DATE:{0}' -f $end.ToString('yyyyMMdd'))
        ('DTEND;VALUE=DATE:{0}' -f $end.AddDays(1).ToString('yyyyMMdd'))
        ('SUMMARY:{0}' -f (& $escapeIcs ('{0} end of support' -f $title)))
        ('DESCRIPTION:{0}' -f (& $escapeIcs $description))
        ('URL:{0}' -f $SiteUrl)
        'CATEGORIES:Azure Local'
        'STATUS:CONFIRMED'
        'TRANSP:TRANSPARENT'
      )) { $lines.Add($line) }

      if ($Reminders) {
        # All-day events start at midnight, so these fire at 09:00 30 and 7 days before
        foreach ($reminder in @(@{ Trigger = '-P29DT15H'; Days = 30 }, @{ Trigger = '-P6DT15H'; Days = 7 })) {
          foreach ($line in @(
            'BEGIN:VALARM'
            'ACTION:DISPLAY'
            ('DESCRIPTION:{0}' -f (& $escapeIcs ('{0} reaches end of support in {1} days' -f $title, $reminder.Days)))
            ('TRIGGER:{0}' -f $reminder.Trigger)
            'END:VALARM'
          )) { $lines.Add($line) }
        }
      }

      $lines.Add('END:VEVENT')
    }

    $lines.Add('END:VCALENDAR')

    (($lines | ForEach-Object { & $foldIcs $_ }) -join "`r`n") + "`r`n"
  }

  # Generate everything in a staging directory and validate it before touching the real files
  $files = [Ordered]@{
    'feed.xml' = $rss.ToString()
    'feed.json' = (($jsonFeed | ConvertTo-Json -Depth 6) + "`n")
    'calendar.ics' = (& $newCalendar $false)
    'calendar-reminders.ics' = (& $newCalendar $true)
    'data/releases.json' = $dataJson
  }

  $legacyJson = ($releases | ConvertTo-Json -Depth 8) + "`n"
  $utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false

  $null = New-Item -Path (Join-Path -Path $staging -ChildPath 'data') -ItemType Directory -Force

  foreach ($_name in $files.Keys) {
    [System.IO.File]::WriteAllText((Join-Path -Path $staging -ChildPath $_name), $files[$_name], $utf8)
  }

  [System.IO.File]::WriteAllText((Join-Path -Path $staging -ChildPath 'legacy.json'), $legacyJson, $utf8)

  & (Join-Path -Path $PSScriptRoot -ChildPath 'Test-SiteOutput.ps1') -SitePath $staging -LegacyJsonPath (Join-Path -Path $staging -ChildPath 'legacy.json') -PreviousDataPath $dataPath -MinimumReleaseCount $MinimumReleaseCount

  # Replace each file atomically (write next to the target, then rename over it). The data file goes last: it is the baseline
  # for change detection, so if this is interrupted the next run sees a change and writes everything again.
  $publish = {
    param ([String]$Source, [String]$Destination)

    $directory = Split-Path -Path $Destination -Parent

    if (-not (Test-Path -Path $directory -PathType Container)) {
      $null = New-Item -Path $directory -ItemType Directory -Force
    }

    $temporary = '{0}.{1}.tmp' -f $Destination, [Guid]::NewGuid().ToString('N')

    try {
      Copy-Item -Path $Source -Destination $temporary -Force
      [System.IO.File]::Move($temporary, $Destination, $true)
    }
    finally {
      if (Test-Path -Path $temporary) {
        Remove-Item -Path $temporary -Force -ErrorAction SilentlyContinue
      }
    }
  }

  & $publish (Join-Path -Path $staging -ChildPath 'legacy.json') $LegacyJsonPath

  foreach ($_name in @($files.Keys | Where-Object { $_ -ne 'data/releases.json' })) {
    & $publish (Join-Path -Path $staging -ChildPath $_name) (Join-Path -Path $OutputPath -ChildPath $_name)
  }

  & $publish (Join-Path -Path $staging -ChildPath 'data/releases.json') $dataPath

  Write-Host ('Generated {0} releases ({1} supported) in {2}' -f $releases.Count, @($releases | Where-Object { $_.supported }).Count, (Resolve-Path -Path $OutputPath))
  & $setOutput 'changed' 'true'
}
catch {
  $message = ($_.Exception.Message -replace '[\r\n]+', ' ').Trim()

  if ($message.Length -gt 900) {
    $message = $message.Substring(0, 900) + '...'
  }

  Write-Host ('::error title=Build failed, nothing was published::{0}' -f $message)
  & $setOutput 'changed' 'false'
  & $setOutput 'error' $message

  throw
}
finally {
  if (Test-Path -Path $staging) {
    Remove-Item -Path $staging -Recurse -Force -ErrorAction SilentlyContinue
  }
}
