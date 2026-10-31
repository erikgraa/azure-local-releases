#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Offline tests for scripts/Build-Site.ps1 and scripts/Test-SiteOutput.ps1. The committed releases array is used as input.
# Run with: Invoke-Pester ./tests

BeforeAll {
  # The tests must not write to the step outputs of the workflow that runs them
  $script:savedGithubOutput = $env:GITHUB_OUTPUT
  Remove-Item -Path Env:\GITHUB_OUTPUT -ErrorAction SilentlyContinue

  $script:repo = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
  $script:build = Join-Path -Path $repo -ChildPath 'scripts/Build-Site.ps1'
  $script:validate = Join-Path -Path $repo -ChildPath 'scripts/Test-SiteOutput.ps1'
  $script:fixture = Join-Path -Path $repo -ChildPath 'json/azure-local-releases.json'

  function New-Sandbox {
    $root = Join-Path -Path $TestDrive -ChildPath ([Guid]::NewGuid().ToString('N'))
    $null = New-Item -Path (Join-Path $root 'site') -ItemType Directory -Force
    $null = New-Item -Path (Join-Path $root 'json') -ItemType Directory -Force

    [PSCustomObject]@{
      Root = $root
      Site = (Join-Path $root 'site')
      Legacy = (Join-Path $root 'json/azure-local-releases.json')
    }
  }

  function Invoke-Build {
    param ($Sandbox, [String]$Source = $fixture)

    & $build -OutputPath $Sandbox.Site -LegacyJsonPath $Sandbox.Legacy -SiteUrl 'https://example.test/' -SourceJsonPath $Source 6>$null
  }

  function Write-Source {
    param ($Sandbox, $Releases, [String]$Name = 'source.json')

    $path = Join-Path -Path $Sandbox.Root -ChildPath $Name
    [System.IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject @($Releases) -Depth 8))
    $path
  }

  function Get-Releases {
    @(Get-Content -Path $fixture -Raw | ConvertFrom-Json -Depth 10 | ForEach-Object {
      foreach ($p in 'availabilityDate', 'firstAvailabilityDate', 'endOfSupportDate') { $_.$p = ([DateTime]$_.$p).ToString('yyyy-MM-dd') }
      $_
    })
  }

  function Get-FileState {
    param ($Sandbox)

    $state = @{}

    foreach ($file in Get-ChildItem -Path $Sandbox.Root -Recurse -File | Where-Object { $_.Name -notlike 'source*.json' }) {
      $state[$file.FullName.Substring($Sandbox.Root.Length)] = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
    }

    $state
  }
}

Describe 'Build-Site.ps1' {
  Context 'with valid input' {
    BeforeAll {
      $script:good = New-Sandbox
      Invoke-Build -Sandbox $good
    }

    It 'writes all outputs' {
      foreach ($file in 'data/releases.json', 'feed.xml', 'feed.json', 'calendar.ics', 'calendar-reminders.ics') {
        (Join-Path $good.Site $file) | Should -Exist
        (Get-Item (Join-Path $good.Site $file)).Length | Should -BeGreaterThan 0
      }

      $good.Legacy | Should -Exist
    }

    It 'passes validation' {
      { & $validate -SitePath $good.Site -LegacyJsonPath $good.Legacy 6>$null } | Should -Not -Throw
    }

    It 'leaves no temporary files behind' {
      Get-ChildItem -Path $good.Root -Recurse -Filter '*.tmp' | Should -BeNullOrEmpty
    }

    It 'writes nothing when the data did not change' {
      $before = Get-FileState $good
      Invoke-Build -Sandbox $good
      $after = Get-FileState $good

      ($after.Keys | Sort-Object) -join '|' | Should -Be (($before.Keys | Sort-Object) -join '|')

      foreach ($key in $before.Keys) { $after[$key] | Should -Be $before[$key] }
    }

    It 'writes a calendar with one all-day event per release and CRLF line endings' {
      $ics = [System.IO.File]::ReadAllText((Join-Path $good.Site 'calendar.ics'))

      ([regex]::Matches($ics, 'BEGIN:VEVENT')).Count | Should -Be (Get-Releases).Count
      $ics | Should -Match '^BEGIN:VCALENDAR\r\nVERSION:2\.0\r\n'
      $ics | Should -Match 'END:VCALENDAR\r\n$'
      $ics | Should -Not -Match '(?<!\r)\n'
      $ics | Should -Match 'DTSTART;VALUE=DATE:\d{8}\r\nDTEND;VALUE=DATE:\d{8}'
      $ics | Should -Not -Match 'VALARM'
    }

    It 'adds reminders only to the reminders calendar' {
      $ics = [System.IO.File]::ReadAllText((Join-Path $good.Site 'calendar-reminders.ics'))

      ([regex]::Matches($ics, 'BEGIN:VALARM')).Count | Should -Be ((Get-Releases).Count * 2)
    }

    It 'keeps UIDs stable when a later build supersedes a release' {
      $before = [System.IO.File]::ReadAllText((Join-Path $good.Site 'calendar.ics'))
      $uidsBefore = [regex]::Matches($before, '(?m)^UID:(.+)\r$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object

      $releases = Get-Releases
      $newest = $releases | Where-Object { $_.version -eq '12.2610.1004.41' }
      $newest.version = '12.2610.1004.42'
      $newest.availabilityDate = '2026-10-29'
      $newest.supersedes = @('12.2610.1004.41')

      $sandbox = New-Sandbox
      Invoke-Build -Sandbox $sandbox -Source (Write-Source $sandbox $releases)
      $after = [System.IO.File]::ReadAllText((Join-Path $sandbox.Site 'calendar.ics'))
      $uidsAfter = [regex]::Matches($after, '(?m)^UID:(.+)\r$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object

      $uidsAfter | Should -Be $uidsBefore
      $uidsBefore.Count | Should -Be ($uidsBefore | Select-Object -Unique).Count
    }

    It 'folds long lines at 75 octets and escapes text' {
      $releases = Get-Releases
      $releases[0].osBuild = 'build; with, special \ chars and a very long text that needs folding ' + ('å' * 60)

      $sandbox = New-Sandbox
      Invoke-Build -Sandbox $sandbox -Source (Write-Source $sandbox $releases)
      $ics = [System.IO.File]::ReadAllText((Join-Path $sandbox.Site 'calendar.ics'))

      foreach ($line in ($ics -split "`r`n")) {
        [System.Text.Encoding]::UTF8.GetByteCount($line) | Should -BeLessOrEqual 75
      }

      ($ics -replace "`r`n ", '') | Should -Match 'build\\; with\\, special \\\\ chars'
    }
  }

  Context 'when the input is bad, nothing is overwritten' {
    BeforeAll {
      $script:sandbox = New-Sandbox
      Invoke-Build -Sandbox $sandbox
      $script:baseline = Get-FileState $sandbox
    }

    It '<name>' -ForEach @(
      @{ Name = 'rejects an empty result'; Make = { @() }; Expect = 'No releases' }
      @{ Name = 'rejects too few releases'; Make = { Get-Releases | Select-Object -First 5 }; Expect = 'Only 5 releases' }
      @{ Name = 'rejects a big drop compared with the published data'; Make = { Get-Releases | Select-Object -First 30 }; Expect = 'more than 10% fewer' }
      @{ Name = 'rejects releases without required fields'; Make = { $r = Get-Releases; $r[3].osBuild = $null; $r }; Expect = 'osBuild is missing' }
      @{ Name = 'rejects unparseable dates'; Make = { $r = Get-Releases; $r[2].endOfSupportDate = 'soon'; $r }; Expect = 'invalid version or date' }
      @{ Name = 'rejects an end of support date that is not 180 days out'; Make = { $r = Get-Releases; $r[2].endOfSupportDate = '2030-01-01'; $r }; Expect = '180 days' }
      @{ Name = 'rejects data where nothing is supported'; Make = { $r = Get-Releases; $r | ForEach-Object { $_.supported = $false }; $r }; Expect = 'No supported releases' }
      @{ Name = 'rejects data older than what is published'; Make = { Get-Releases | Where-Object { $_.firstAvailabilityDate -lt '2026-09-01' } | Select-Object -First 38 }; Expect = 'older than the newest published' }
    ) {
      $source = Write-Source $sandbox (& $Make) 'source-bad.json'

      { Invoke-Build -Sandbox $sandbox -Source $source } | Should -Throw -ExpectedMessage "*$Expect*"

      $after = Get-FileState $sandbox

      ($after.Keys | Sort-Object) -join '|' | Should -Be (($baseline.Keys | Sort-Object) -join '|')

      foreach ($key in $baseline.Keys) { $after[$key] | Should -Be $baseline[$key] -Because "$key must not change" }
    }

    It 'rejects a source that is not JSON' {
      $source = Join-Path $sandbox.Root 'source-garbage.json'
      [System.IO.File]::WriteAllText($source, '<html>Service unavailable</html>')

      { Invoke-Build -Sandbox $sandbox -Source $source } | Should -Throw

      $after = Get-FileState $sandbox
      foreach ($key in $baseline.Keys) { $after[$key] | Should -Be $baseline[$key] }
    }

    It 'rejects a missing source' {
      { Invoke-Build -Sandbox $sandbox -Source (Join-Path $sandbox.Root 'does-not-exist.json') } | Should -Throw
    }

    It 'does not create files on a first run that fails' {
      $fresh = New-Sandbox

      { Invoke-Build -Sandbox $fresh -Source (Write-Source $fresh @()) } | Should -Throw

      Get-ChildItem -Path $fresh.Root -Recurse -File | Where-Object { $_.Name -notlike 'source*.json' } | Should -BeNullOrEmpty
    }

    It 'reports the reason as the step output "error"' {
      $output = Join-Path $sandbox.Root 'github-output.txt'
      $env:GITHUB_OUTPUT = $output

      try {
        { Invoke-Build -Sandbox $sandbox -Source (Write-Source $sandbox @() 'source-bad.json') } | Should -Throw
      }
      finally {
        Remove-Item Env:\GITHUB_OUTPUT
      }

      $text = Get-Content -Path $output -Raw
      $text | Should -Match 'changed=false'
      $text | Should -Match 'error=No releases'
    }
  }
}

Describe 'Test-SiteOutput.ps1' {
  BeforeAll {
    $script:valid = New-Sandbox
    Invoke-Build -Sandbox $valid

    function Copy-Valid {
      $copy = New-Sandbox
      Copy-Item -Path (Join-Path $valid.Site '*') -Destination $copy.Site -Recurse
      Copy-Item -Path $valid.Legacy -Destination $copy.Legacy
      $copy
    }
  }

  It '<name>' -ForEach @(
    @{ Name = 'rejects an empty data file'; File = 'data/releases.json'; Content = ''; Expect = 'empty' }
    @{ Name = 'rejects data without releases'; File = 'data/releases.json'; Content = '{"generatedAt":"2026-10-31T06:00:00Z","source":"x","releases":[],"trains":[],"newDeployments":[]}'; Expect = 'Only 0 releases' }
    @{ Name = 'rejects a feed that is not well formed'; File = 'feed.xml'; Content = '<rss><channel><item>'; Expect = 'not well formed' }
    @{ Name = 'rejects an empty JSON Feed'; File = 'feed.json'; Content = '{"version":"https://jsonfeed.org/version/1.1","items":[]}'; Expect = 'no items' }
    @{ Name = 'rejects an empty calendar'; File = 'calendar.ics'; Content = ''; Expect = 'calendar.ics is missing or empty' }
    @{ Name = 'rejects a calendar without events'; File = 'calendar.ics'; Content = "BEGIN:VCALENDAR`r`nVERSION:2.0`r`nPRODID:-//x//EN`r`nEND:VCALENDAR`r`n"; Expect = 'has no events' }
    @{ Name = 'rejects a truncated calendar'; File = 'calendar.ics'; Content = 'BEGIN:VCALENDAR'; Expect = 'BEGIN:VCALENDAR/END:VCALENDAR' }
  ) {
    $copy = Copy-Valid
    [System.IO.File]::WriteAllText((Join-Path $copy.Site $File), $Content)

    { & $validate -SitePath $copy.Site -LegacyJsonPath $copy.Legacy 6>$null } | Should -Throw -ExpectedMessage "*$Expect*"
  }

  It 'rejects a calendar with LF line endings' {
    $copy = Copy-Valid
    $path = Join-Path $copy.Site 'calendar.ics'
    [System.IO.File]::WriteAllText($path, ([System.IO.File]::ReadAllText($path) -replace "`r`n", "`n"))

    { & $validate -SitePath $copy.Site -LegacyJsonPath $copy.Legacy 6>$null } | Should -Throw '*CRLF*'
  }

  It 'rejects a calendar whose dates do not match the data' {
    $copy = Copy-Valid
    $path = Join-Path $copy.Site 'calendar.ics'
    $ics = [System.IO.File]::ReadAllText($path)
    [System.IO.File]::WriteAllText($path, ([regex]'DTSTART;VALUE=DATE:\d{8}').Replace($ics, 'DTSTART;VALUE=DATE:20300101', 1))

    { & $validate -SitePath $copy.Site -LegacyJsonPath $copy.Legacy 6>$null } | Should -Throw '*do not match*'
  }

  It 'rejects a missing legacy JSON file' {
    { & $validate -SitePath $valid.Site -LegacyJsonPath (Join-Path $TestDrive 'nope.json') 6>$null } | Should -Throw '*legacy JSON*'
  }

  It 'reports stale data with -FreshnessOnly' {
    $output = Join-Path $TestDrive 'freshness-output.txt'
    $env:GITHUB_OUTPUT = $output

    try {
      & $validate -SitePath $valid.Site -FreshnessOnly -MaxAgeDays 60 3>$null 6>$null
      & $validate -SitePath $valid.Site -FreshnessOnly -MaxAgeDays 60 -Now ([DateTime]::UtcNow.AddDays(90)) 3>$null 6>$null
    }
    finally {
      Remove-Item Env:\GITHUB_OUTPUT
    }

    $lines = Get-Content -Path $output
    ($lines | Where-Object { $_ -like 'stale=*' }) | Should -Be @('stale=false', 'stale=true')
  }
}

AfterAll {
  if ($script:savedGithubOutput) { $env:GITHUB_OUTPUT = $script:savedGithubOutput }
}
