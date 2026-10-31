<#
  .SYNOPSIS
  Validates the generated site files (JSON data, RSS, JSON Feed, ICS calendars and the legacy JSON array).

  .DESCRIPTION
  Used by Build-Site.ps1 to validate freshly generated files before anything is published, and by the workflow as a
  final gate before committing and deploying. Collects every problem found and throws one error listing them all, so
  a parser or script failure can never result in empty or degraded files being published.

  Checks: files exist and are non-empty and well formed, a minimum number of releases, required fields and formats,
  sane dates (end of support is first availability + 180 days), consistent content across the data, feeds and
  calendars, RFC 5545 structure of the calendars, and optionally a comparison with the previously published data.

  With -FreshnessOnly only the age of generatedAt is checked (used for the staleness alert).
#>

[CmdletBinding()]
param (
  [Parameter(Mandatory=$false)]
  [String]$SitePath = (Join-Path -Path $PSScriptRoot -ChildPath '../site'),

  [Parameter(Mandatory=$false)]
  [String]$LegacyJsonPath = (Join-Path -Path $PSScriptRoot -ChildPath '../json/azure-local-releases.json'),

  # Previously published releases.json to compare with. Skipped if it does not exist or cannot be read.
  [Parameter(Mandatory=$false)]
  [String]$PreviousDataPath,

  [Parameter(Mandatory=$false)]
  [Int]$MinimumReleaseCount = 20,

  # Largest accepted drop in the number of releases compared with the previous data
  [Parameter(Mandatory=$false)]
  [Int]$MaxDropPercent = 10,

  # Only check that generatedAt is not older than -MaxAgeDays. Exposes the result as the step output "stale".
  [Parameter(Mandatory=$false)]
  [Switch]$FreshnessOnly,

  [Parameter(Mandatory=$false)]
  [Int]$MaxAgeDays = 60,

  [Parameter(Mandatory=$false)]
  [DateTime]$Now = [DateTime]::UtcNow
)

$ErrorActionPreference = 'Stop'

$invariant = [Globalization.CultureInfo]::InvariantCulture
$errors = New-Object -TypeName System.Collections.Generic.List[String]

function Add-Problem {
  param ([String]$Message)
  $errors.Add($Message)
}

function ConvertTo-Day {
  param ($Value)

  if ($Value -is [DateTime]) {
    return $Value.Date
  }

  $parsed = [DateTime]::MinValue

  if ($Value -is [String] -and [DateTime]::TryParseExact($Value, 'yyyy-MM-dd', $invariant, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
    return $parsed
  }

  return $null
}

function Read-Json {
  param ([String]$Path, [String]$Name)

  if (-not (Test-Path -Path $Path -PathType Leaf)) {
    Add-Problem ('{0} is missing' -f $Name)
    return $null
  }

  if ((Get-Item -Path $Path).Length -eq 0) {
    Add-Problem ('{0} is empty' -f $Name)
    return $null
  }

  try {
    return (Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 10)
  }
  catch {
    Add-Problem ('{0} is not valid JSON: {1}' -f $Name, $_.Exception.Message)
    return $null
  }
}

$dataPath = Join-Path -Path $SitePath -ChildPath 'data/releases.json'

if ($FreshnessOnly) {
  $data = Read-Json -Path $dataPath -Name 'data/releases.json'
  $generated = $null

  if ($null -ne $data -and $data.generatedAt) {
    $generated = ([DateTime]$data.generatedAt).ToUniversalTime()
  }

  if ($null -eq $generated) {
    Add-Problem 'generatedAt could not be read from data/releases.json'
  }
  else {
    $age = [Math]::Floor(($Now.ToUniversalTime() - $generated).TotalDays)

    if ($age -gt $MaxAgeDays) {
      Add-Problem ('The data was last refreshed {0:yyyy-MM-dd} ({1} days ago, the limit is {2}). The data changes at least monthly, so the parser or the workflow may have stopped working.' -f $generated, $age, $MaxAgeDays)
    }
  }

  $stale = $errors.Count -gt 0
  $message = ($errors -join ' ')

  Write-Host ('stale={0}' -f $stale.ToString().ToLower())

  if ($stale) {
    Write-Warning $message
  }

  if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value ('stale={0}' -f $stale.ToString().ToLower())
    Add-Content -Path $env:GITHUB_OUTPUT -Value ('stale_message={0}' -f ($message -replace '[\r\n]+', ' '))
  }

  return
}

$data = Read-Json -Path $dataPath -Name 'data/releases.json'
$releases = @()

if ($null -ne $data) {
  $releases = @($data.releases | Where-Object { $null -ne $_ })

  $generated = $null

  if ($data.generatedAt) {
    try { $generated = ([DateTime]$data.generatedAt).ToUniversalTime() } catch { }
  }

  if ($null -eq $generated) {
    Add-Problem 'generatedAt is missing or not a date'
  }
  elseif ($generated -gt $Now.AddDays(1)) {
    Add-Problem ('generatedAt ({0:u}) is in the future' -f $generated)
  }

  if (-not $data.source) {
    Add-Problem 'source is missing'
  }

  if ($releases.Count -lt $MinimumReleaseCount) {
    Add-Problem ('Only {0} releases (expected at least {1}), the documentation format may have changed' -f $releases.Count, $MinimumReleaseCount)
  }

  if (-not ($releases | Where-Object { $_.supported -eq $true })) {
    Add-Problem 'No supported releases'
  }

  $seen = @{}
  $oldest = [DateTime]'2023-01-01'

  foreach ($_release in $releases) {
    $id = if ($_release.version) { [String]$_release.version } else { '(release without version)' }

    foreach ($field in 'version', 'osBuild', 'osVersion', 'releaseTrain', 'release', 'releaseShortened') {
      if ([String]::IsNullOrWhiteSpace([String]$_release.$field)) {
        Add-Problem ('{0}: {1} is missing' -f $id, $field)
      }
    }

    if ($_release.version -and [String]$_release.version -notmatch '^\d+\.\d{4}\.\d+\.\d+$') {
      Add-Problem ('{0}: version has an unexpected format' -f $id)
    }

    if ($seen.ContainsKey($id)) {
      Add-Problem ('{0}: duplicate version' -f $id)
    }

    $seen[$id] = $true

    if ($_release.supported -isnot [Boolean]) {
      Add-Problem ('{0}: supported is not true or false' -f $id)
    }

    if (-not $_release.urls -or [String]$_release.urls.news -notmatch '^https://') {
      Add-Problem ('{0}: urls.news is missing' -f $id)
    }

    $first = ConvertTo-Day $_release.firstAvailabilityDate
    $latest = ConvertTo-Day $_release.availabilityDate
    $end = ConvertTo-Day $_release.endOfSupportDate

    foreach ($pair in @(@('firstAvailabilityDate', $first), @('availabilityDate', $latest), @('endOfSupportDate', $end))) {
      if ($null -eq $pair[1]) {
        Add-Problem ('{0}: {1} is missing or not a yyyy-MM-dd date' -f $id, $pair[0])
      }
      elseif ($pair[1] -lt $oldest -or $pair[1] -gt $Now.Date.AddDays(400)) {
        Add-Problem ('{0}: {1} ({2:yyyy-MM-dd}) is not a sane date' -f $id, $pair[0], $pair[1])
      }
    }

    if ($null -ne $first -and $null -ne $latest) {
      if ($first -gt $latest) {
        Add-Problem ('{0}: firstAvailabilityDate is after availabilityDate' -f $id)
      }

      if ($latest -gt $Now.Date.AddDays(14)) {
        Add-Problem ('{0}: availabilityDate ({1:yyyy-MM-dd}) is in the future' -f $id, $latest)
      }
    }

    if ($null -ne $first -and $null -ne $end -and $end -ne $first.AddDays(180)) {
      Add-Problem ('{0}: endOfSupportDate is not 180 days after firstAvailabilityDate' -f $id)
    }
  }

  $trains = @($data.trains | Where-Object { $null -ne $_ })

  if ($trains.Count -eq 0) {
    Add-Problem 'trains is empty'
  }

  foreach ($_train in $trains) {
    if (-not $_train.releaseTrain -or @($_train.versions).Count -eq 0) {
      Add-Problem 'A release train has no name or no versions'
    }
  }

  foreach ($_version in @($data.newDeployments)) {
    if (-not $seen.ContainsKey([String]$_version)) {
      Add-Problem ('newDeployments refers to unknown version {0}' -f $_version)
    }
  }

  if (@($data.newDeployments).Count -eq 0) {
    Add-Problem 'newDeployments is empty'
  }

  if ($PreviousDataPath -and (Test-Path -Path $PreviousDataPath -PathType Leaf)) {
    $previous = $null

    try { $previous = Get-Content -Path $PreviousDataPath -Raw | ConvertFrom-Json -Depth 10 } catch { }

    if ($null -ne $previous -and @($previous.releases).Count -gt 0) {
      $previousReleases = @($previous.releases)

      # Releases are only ever added, so a big drop means parsing went wrong
      if ($releases.Count -lt [Math]::Floor($previousReleases.Count * (100 - $MaxDropPercent) / 100)) {
        Add-Problem ('Only {0} releases but {1} were published before (more than {2}% fewer), the documentation format may have changed' -f $releases.Count, $previousReleases.Count, $MaxDropPercent)
      }

      $latestPrevious = ($previousReleases | ForEach-Object { ConvertTo-Day $_.firstAvailabilityDate } | Where-Object { $null -ne $_ } | Sort-Object | Select-Object -Last 1)
      $latestCurrent = ($releases | ForEach-Object { ConvertTo-Day $_.firstAvailabilityDate } | Where-Object { $null -ne $_ } | Sort-Object | Select-Object -Last 1)

      if ($null -ne $latestPrevious -and $latestCurrent -lt $latestPrevious) {
        Add-Problem ('The newest release ({0:yyyy-MM-dd}) is older than the newest published release ({1:yyyy-MM-dd})' -f $latestCurrent, $latestPrevious)
      }
    }
  }
}

# Legacy plain array
$legacy = Read-Json -Path $LegacyJsonPath -Name 'legacy JSON array'

if ($null -ne $legacy -and $null -ne $data -and @($legacy).Count -ne $releases.Count) {
  Add-Problem ('The legacy JSON array has {0} releases but the data has {1}' -f @($legacy).Count, $releases.Count)
}

# RSS
$rssIds = @()
$rssPath = Join-Path -Path $SitePath -ChildPath 'feed.xml'

if (-not (Test-Path -Path $rssPath -PathType Leaf) -or (Get-Item -Path $rssPath).Length -eq 0) {
  Add-Problem 'feed.xml is missing or empty'
}
else {
  try {
    $xml = New-Object -TypeName System.Xml.XmlDocument
    $xml.Load($rssPath)
    $items = @($xml.SelectNodes('/rss/channel/item'))

    if ($items.Count -eq 0) {
      Add-Problem 'feed.xml has no items'
    }

    foreach ($_item in $items) {
      foreach ($field in 'title', 'link', 'guid', 'pubDate', 'description') {
        if ([String]::IsNullOrWhiteSpace($_item.SelectSingleNode($field).InnerText)) {
          Add-Problem ('feed.xml: an item has no {0}' -f $field)
        }
      }
    }

    $rssIds = @($items | ForEach-Object { $_.SelectSingleNode('guid').InnerText })
  }
  catch {
    Add-Problem ('feed.xml is not well formed: {0}' -f $_.Exception.Message)
  }
}

# JSON Feed
$jsonFeed = Read-Json -Path (Join-Path -Path $SitePath -ChildPath 'feed.json') -Name 'feed.json'

if ($null -ne $jsonFeed) {
  $feedItems = @($jsonFeed.items | Where-Object { $null -ne $_ })

  if ($feedItems.Count -eq 0) {
    Add-Problem 'feed.json has no items'
  }

  if ($jsonFeed.version -notlike 'https://jsonfeed.org/version/*') {
    Add-Problem 'feed.json has no valid version'
  }

  foreach ($_item in $feedItems) {
    if (-not $_item.id -or -not $_item.title -or -not $_item.date_published) {
      Add-Problem 'feed.json: an item has no id, title or date_published'
    }
  }

  if ($rssIds.Count -gt 0 -and (($rssIds | Sort-Object) -join '|') -cne (($feedItems | ForEach-Object { $_.id } | Sort-Object) -join '|')) {
    Add-Problem 'feed.xml and feed.json do not contain the same items'
  }

  if ($releases.Count -gt 0 -and $feedItems.Count -gt 0) {
    $newest = $releases | Sort-Object -Property @{ Expression = { ConvertTo-Day $_.availabilityDate }; Descending = $true } | Select-Object -First 1

    if (-not ($feedItems | Where-Object { $_.id -eq ('azure-local-{0}' -f $newest.version) })) {
      Add-Problem ('The newest release {0} is missing from the feeds' -f $newest.version)
    }
  }
}

# Calendars
$calendarUids = @{}

foreach ($calendar in @(@{ File = 'calendar.ics'; Alarms = $false }, @{ File = 'calendar-reminders.ics'; Alarms = $true })) {
  $name = $calendar.File
  $path = Join-Path -Path $SitePath -ChildPath $name

  if (-not (Test-Path -Path $path -PathType Leaf) -or (Get-Item -Path $path).Length -eq 0) {
    Add-Problem ('{0} is missing or empty' -f $name)
    continue
  }

  $bytes = [System.IO.File]::ReadAllBytes($path)
  $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)

  if ($text -notmatch "\r\n$") {
    Add-Problem ('{0}: does not end with CRLF' -f $name)
  }

  if ($text -match "(?<!\r)\n") {
    Add-Problem ('{0}: contains line endings other than CRLF' -f $name)
  }

  $rawLines = $text -split "`r`n"

  if ($rawLines[-1] -eq '') {
    $rawLines = $rawLines[0..($rawLines.Count - 2)]
  }

  $tooLong = @($rawLines | Where-Object { [System.Text.Encoding]::UTF8.GetByteCount($_) -gt 75 })

  if ($tooLong.Count -gt 0) {
    Add-Problem ('{0}: {1} lines are longer than 75 octets and not folded' -f $name, $tooLong.Count)
  }

  $lines = @(($text -replace "\r\n[ \t]", '') -split "`r`n" | Where-Object { $_ -ne '' })

  if ($lines.Count -lt 2 -or $lines[0] -cne 'BEGIN:VCALENDAR' -or $lines[-1] -cne 'END:VCALENDAR') {
    Add-Problem ('{0}: is not wrapped in BEGIN:VCALENDAR/END:VCALENDAR' -f $name)
    continue
  }

  if ($lines -cnotcontains 'VERSION:2.0') {
    Add-Problem ('{0}: VERSION:2.0 is missing' -f $name)
  }

  if (-not ($lines | Where-Object { $_ -cmatch '^PRODID:.+' })) {
    Add-Problem ('{0}: PRODID is missing' -f $name)
  }

  $events = New-Object -TypeName System.Collections.Generic.List[Object]
  $current = $null
  $inAlarm = $false
  $alarm = $null

  foreach ($line in $lines[1..($lines.Count - 2)]) {
    switch -CaseSensitive ($line) {
      'BEGIN:VEVENT' {
        if ($null -ne $current) { Add-Problem ('{0}: nested VEVENT' -f $name) }
        $current = @{ Props = @{}; Alarms = New-Object -TypeName System.Collections.Generic.List[Object] }
        continue
      }
      'END:VEVENT' {
        if ($null -eq $current) { Add-Problem ('{0}: END:VEVENT without BEGIN' -f $name) }
        else { $events.Add($current); $current = $null }
        continue
      }
      'BEGIN:VALARM' {
        if ($null -eq $current) { Add-Problem ('{0}: VALARM outside VEVENT' -f $name) }
        $inAlarm = $true
        $alarm = @{}
        continue
      }
      'END:VALARM' {
        if ($inAlarm) { $current.Alarms.Add($alarm) }
        $inAlarm = $false
        continue
      }
      default {
        if ($line -cmatch '^([A-Z0-9-]+)((?:;[^:]*)?):(.*)$') {
          $key = $Matches[1] + $Matches[2]

          if ($inAlarm) { $alarm[$key] = $Matches[3] }
          elseif ($null -ne $current) {
            if ($current.Props.ContainsKey($key)) { Add-Problem ('{0}: duplicate {1}' -f $name, $key) }
            $current.Props[$key] = $Matches[3]
          }
        }
        elseif ($line -notmatch '^BEGIN:|^END:') {
          Add-Problem ('{0}: invalid content line "{1}"' -f $name, $line)
        }
      }
    }
  }

  if ($null -ne $current -or $inAlarm) {
    Add-Problem ('{0}: unterminated VEVENT or VALARM' -f $name)
  }

  if ($events.Count -eq 0) {
    Add-Problem ('{0}: has no events' -f $name)
  }

  $uids = @{}
  $dates = New-Object -TypeName System.Collections.Generic.List[String]

  foreach ($_event in $events) {
    $p = $_event.Props
    $uid = [String]$p['UID']

    if (-not $uid) { Add-Problem ('{0}: an event has no UID' -f $name) }
    elseif ($uids.ContainsKey($uid)) { Add-Problem ('{0}: duplicate UID {1}' -f $name, $uid) }
    else { $uids[$uid] = $true }

    foreach ($required in 'SUMMARY', 'DTSTAMP') {
      if (-not $p[$required]) { Add-Problem ('{0}: {1} has no {2}' -f $name, $uid, $required) }
    }

    if ($p['DTSTAMP'] -and $p['DTSTAMP'] -cnotmatch '^\d{8}T\d{6}Z$') {
      Add-Problem ('{0}: {1} has an invalid DTSTAMP' -f $name, $uid)
    }

    $start = [DateTime]::MinValue
    $end = [DateTime]::MinValue

    if (-not $p.ContainsKey('DTSTART;VALUE=DATE') -or -not [DateTime]::TryParseExact($p['DTSTART;VALUE=DATE'], 'yyyyMMdd', $invariant, [Globalization.DateTimeStyles]::None, [ref]$start)) {
      Add-Problem ('{0}: {1} has no valid all-day DTSTART' -f $name, $uid)
    }
    else {
      $dates.Add($start.ToString('yyyy-MM-dd'))

      if (-not $p.ContainsKey('DTEND;VALUE=DATE') -or -not [DateTime]::TryParseExact($p['DTEND;VALUE=DATE'], 'yyyyMMdd', $invariant, [Globalization.DateTimeStyles]::None, [ref]$end) -or $end -ne $start.AddDays(1)) {
        Add-Problem ('{0}: {1} has an invalid DTEND (must be the day after DTSTART)' -f $name, $uid)
      }
    }

    if ($calendar.Alarms) {
      if ($_event.Alarms.Count -eq 0) { Add-Problem ('{0}: {1} has no reminder' -f $name, $uid) }
    }
    elseif ($_event.Alarms.Count -gt 0) {
      Add-Problem ('{0}: {1} has a reminder but this calendar is meant to have none' -f $name, $uid)
    }

    foreach ($_alarm in $_event.Alarms) {
      if ($_alarm['ACTION'] -cne 'DISPLAY' -or -not $_alarm['TRIGGER'] -or -not $_alarm['DESCRIPTION']) {
        Add-Problem ('{0}: {1} has an incomplete VALARM' -f $name, $uid)
      }
    }
  }

  $calendarUids[$name] = @($uids.Keys | Sort-Object)

  if ($releases.Count -gt 0) {
    if ($events.Count -ne $releases.Count) {
      Add-Problem ('{0}: has {1} events but the data has {2} releases' -f $name, $events.Count, $releases.Count)
    }

    $expected = (@($releases | ForEach-Object { (ConvertTo-Day $_.endOfSupportDate).ToString('yyyy-MM-dd') } | Sort-Object) -join '|')

    if ((@($dates | Sort-Object) -join '|') -cne $expected) {
      Add-Problem ('{0}: the event dates do not match the end of support dates in the data' -f $name)
    }
  }
}

if ($calendarUids.Count -eq 2 -and ($calendarUids['calendar.ics'] -join '|') -cne ($calendarUids['calendar-reminders.ics'] -join '|')) {
  Add-Problem 'calendar.ics and calendar-reminders.ics do not contain the same events'
}

if ($errors.Count -gt 0) {
  $message = 'Validation failed with {0} problem(s): {1}' -f $errors.Count, (($errors | Select-Object -First 15) -join '; ')

  if ($errors.Count -gt 15) {
    $message += '; ...'
  }

  throw $message
}

Write-Host ('Validated {0} releases, feeds and calendars in {1}' -f $releases.Count, $SitePath)
