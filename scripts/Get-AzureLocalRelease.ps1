<#PSScriptInfo
  .VERSION 2.0
  .GUID 082911ff-1d75-4cbc-9391-ab093db0aaab
  .AUTHOR erikgraa
#>

<#

  .DESCRIPTION
  Script to enumerate Azure Local releases, including when each release reaches end of support.

#>

function Get-AzureLocalRelease {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [System.Uri]$Uri = 'https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2',

    [Parameter(Mandatory=$false)]
    [Switch]$SupportedReleases,

    [Parameter(Mandatory=$false)]
    [ValidateSet('String', 'Version')]
    [String]$OutputType = 'String'
  )

  begin {}

  process {
    # Each release is supported for six months (180 days) after it first became available
    $supportDays = 180

    $baseUrl = $Uri.ToString().Substring(0, $Uri.ToString().Length - $Uri.ToString().Split('/')[-1].Length)

    $documentation = [String](Invoke-RestMethod -Uri $Uri)

    # Solution update ZIPs for limited connectivity scenarios. These are optional enrichment, so failures are not fatal.
    $solutionUpdateHash = @{}

    try {
      $solutionUpdateUri = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-stack-docs/refs/heads/main/azure-local/update/import-discover-updates-offline-23h2.md'
      $solutionUpdatePattern = '\[(\d+\.\d+\.\d+\.\d+)\]\((https://[^)\s]+\.zip)\).*?\|\s*([0-9A-Fa-f]{64})\s*\|'

      foreach ($_match in [Regex]::Matches([String](Invoke-RestMethod -Uri $solutionUpdateUri), $solutionUpdatePattern)) {
        $solutionUpdateHash[$_match.Groups[1].Value] = [Ordered]@{
          'uri' = $_match.Groups[2].Value
          'fileHash' = $_match.Groups[3].Value.ToUpper()
        }
      }
    }
    catch {
      Write-Warning ('Solution update information could not be retrieved: {0}' -f $_)
    }

    # The version listed in a table row is the latest build of a release. Earlier builds follow as "Supersedes: <version> Availability date: <date>".
    # The first cell holds the builds, the second the OS build and any remaining cells contain links.
    $rowPattern = '(?s)<tr>\s*<td>(.*?)</td>\s*<td>(\d+\.\d+)</td>(.*?)</tr>'
    $buildPattern = '(\d+\.\d+\.\d+\.\d+)[^0-9]*?Availability date:\s*(\d{4}-\d{2}-\d{2})'

    # "New deployments of this software use the <strong>12.2610.1004.41</strong> build."
    $newDeploymentVersions = @([Regex]::Matches($documentation, 'New deployments[^<]*?use the\s*<strong>(\d+\.\d+\.\d+\.\d+)</strong>') | ForEach-Object { $_.Groups[1].Value })

    $versions = @{}

    foreach ($_row in [Regex]::Matches($documentation, $rowPattern)) {
      $cell = $_row.Groups[1].Value -replace '<[^>]+>', ' '

      $builds = @([Regex]::Matches($cell, $buildPattern) | ForEach-Object {
        [PSCustomObject]@{
          'version' = $_.Groups[1].Value
          'availabilityDate' = $_.Groups[2].Value
        }
      })

      if ($builds.Count -eq 0) {
        Write-Warning ('Skipping table row without version and availability date: {0}' -f $cell.Trim())
        continue
      }

      $latestBuild = $builds[0]

      # The oldest build in the chain is when the release first became available, which is what the support period counts from
      $firstAvailabilityDate = $builds[-1].availabilityDate

      # Guard against typos in the documentation where a build is dated before the build it supersedes
      $availabilityDate = if ([DateTime]$latestBuild.availabilityDate -lt [DateTime]$firstAvailabilityDate) { $firstAvailabilityDate } else { $latestBuild.availabilityDate }

      $fullVersionString = $latestBuild.version
      $parts = $fullVersionString.Split('.')

      $linkPaths = @([Regex]::Matches($_row.Groups[3].Value, '<a href="([^"]+)"') | ForEach-Object { $_.Groups[1].Value.Replace('&amp;', '&') })

      $link = {
        param ($Pattern, $Fallback)

        $path = $linkPaths | Where-Object { $_ -match $Pattern } | Select-Object -First 1

        if ($null -eq $path) {
          $path = $Fallback
        }

        '{0}{1}' -f $baseUrl, $path
      }

      $osBuild = $_row.Groups[2].Value
      $endOfSupportDate = ([DateTime]$firstAvailabilityDate).AddDays($supportDays)

      $fullVersion = if ($OutputType -eq 'Version') { [Version]$fullVersionString } else { $fullVersionString }

      $hash = [Ordered]@{}

      $hash.Add('version', $fullVersion)
      $hash.Add('availabilityDate', $availabilityDate)
      $hash.Add('firstAvailabilityDate', $firstAvailabilityDate)
      $hash.Add('newDeployments', ($newDeploymentVersions -contains $fullVersionString))
      $hash.Add('osBuild', $osBuild)
      $hash.Add('osVersion', $(if ($osBuild -like '26100.*') { '24H2' } else { '23H2' }))
      $hash.Add('releaseTrain', $parts[1])
      $hash.Add('release', ('{0}.{1}.{2}' -f $parts[1], $parts[2], $parts[3]))
      $hash.Add('releaseShortened', ('{0}.{1}' -f $parts[1], $parts[2]))
      # Releases from 2408 onwards are "baseline releases"
      $hash.Add('baselineRelease', ([Int]$parts[1] -ge 2408))
      $hash.Add('endOfSupportDate', $endOfSupportDate.ToString('yyyy-MM-dd'))
      $hash.Add('supported', ((Get-Date).Date -le $endOfSupportDate))
      $hash.Add('supersedes', @($builds | Select-Object -Skip 1))
      $hash.Add('solutionUpdate', $(if ($solutionUpdateHash.ContainsKey($fullVersionString)) { $solutionUpdateHash[$fullVersionString] } else { @{} }))
      $hash.Add('urls', [Ordered]@{
        'security' = (& $link '^security-update' 'security-update/security-update')
        'news' = (& $link '^whats-new' 'whats-new')
        'issues' = (& $link '^known-issues?' 'known-issues')
      })

      # The same version can be listed in more than one table
      if (-not $versions.ContainsKey($fullVersionString)) {
        $versions[$fullVersionString] = New-Object -TypeName PSCustomObject -Property $hash
      }
    }

    if ($versions.Count -eq 0) {
      throw ('No releases found at {0}, format or URL may have changed' -f $Uri)
    }

    $releases = $versions.Values | Sort-Object -Property @{ Expression = { [DateTime]$_.firstAvailabilityDate } }, @{ Expression = { [Version]$_.version } }

    if ($PSBoundParameters.ContainsKey('SupportedReleases')) {
      $releases | Where-Object { [DateTime]$_.endOfSupportDate -gt (Get-Date) }
    }
    else {
      $releases
    }
  }

  end {}
}
