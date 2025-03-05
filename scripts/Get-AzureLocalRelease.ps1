function Get-AzureLocalRelease {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    [System.Uri]$Uri = 'https://learn.microsoft.com/en-us/azure/azure-local/release-information-23h2',

    [Parameter(Mandatory=$false)]
    [Switch]$SkipEndOfSupportReleases,

    [Parameter(Mandatory=$false)]
    [ValidateSet('String', 'Version')]
    [String]$OutputType = 'String'
  )

  begin {}

  process {
    try {
      $baseUrl = $Uri.ToString().Substring(0, $Uri.ToString().Length-$Uri.ToString().Split('/')[-1].Length)

      $documentation = Invoke-RestMethod -Uri $uri

      # ISO 8601
      $tablePattern = "(?ms)<tr>\n<td>\d+\.\d+\.\d+\.\d+.*?Availability date.*?<\/td>\n<\/tr>"

      $entryPattern = '(?ms)<tr>\n<td>(\d+\.\d+\.\d+\.\d+)\s+<br><br>\s+Availability date:\s+(\d{4,4}-\d{2,2}-\d{2,2})<\/td>\n<td>(\d+.\d+)<\/td>\n<td><a href="(.+?)".*?>((\w+) OS security update)<\/a><\/td>\n<td><a href="(.+?)".*?>(Features and improvements)<\/a><\/td>\n<td><a href="(.+?)".*?>(Known issues)<\/a><\/td>\n<\/tr>'

      $table = (Select-String -InputObject $documentation -Pattern $tablePattern -AllMatches).Matches.Groups

      if ($null -eq $table) {
        throw ('No releases found at {0}, format or URL may have changed' -f $Uri)
      }

      $versions = @()

      for($i=$table.Length-1; $i -ge 0; $i--) {
        $_entry = Select-String -Pattern $entryPattern -InputObject $table[$i].Value

        $fullVersion = [version]$_entry.Matches.Groups[1].Value

        # Releases after 2408.0 are "baseline releases"
        $baselineReleaseThreshold = [version]'10.2408.0.0'

        $baselineRelease = if ($fullVersion -ge $baselineReleaseThreshold) {
            $true
        }
        else {
            $false
        }

        # The first release of a release train is a feature build. Any subsequent release within a release train is a cumulative update build.
        $buildType = if ($null -eq ($versions | Where-Object { $_.releaseTrain -eq $_entry.Matches.Groups[1].Value.Split('.')[1] })) {
          'Feature'
        }
        else {
          'Cumulative'
        }

        if ($OutputType -eq 'String') {
          $fullVersion = $fullVersion.ToString()
        }    

        $hash = [Ordered]@{}

        $release = ('{0}.{1}.{2}' -f $_entry.Matches.Groups[1].Value.Split('.')[1], $_entry.Matches.Groups[1].Value.Split('.')[2], $_entry.Matches.Groups[1].Value.Split('.')[3])
        $releaseShortened = ('{0}.{1}' -f $_entry.Matches.Groups[1].Value.Split('.')[1], $_entry.Matches.Groups[1].Value.Split('.')[2])

        $endOfSupportDate = (Get-Date -Date ([DateTime]$_entry.Matches.Groups[2].Value).AddDays(180) -UFormat '%Y-%m-%d')

        $endOfSupport = if ([DateTime]::Now -le $endOfSupportDate) {
            $false
        }
        else {
            $true
        }

        $hash.Add('version', $fullVersion)
        $hash.Add('availabilityDate', $_entry.Matches.Groups[2].Value)
        $hash.Add('osBuild', $_entry.Matches.Groups[3].Value)
        $hash.Add('releaseTrain', $_entry.Matches.Groups[1].Value.Split('.')[1])
        $hash.Add('release', $release)
        $hash.Add('releaseShortened', $releaseShortened)
        $hash.Add('baselineRelease', $baselineRelease)
        $hash.Add('buildType', $buildType)
        $hash.Add('endOfSupportDate', (Get-Date -Date ([DateTime]$_entry.Matches.Groups[2].Value).AddDays(180) -UFormat '%Y-%m-%d'))
        $hash.add('endOfSupport', $endOfSupport)
        $hash.Add('urls', @{
            'security' = ('{0}{1}' -f $baseUrl, $_entry.Matches.Groups[-7].Value).Replace('&amp;','&')
            'news' = ('{0}{1}' -f $baseUrl, $_entry.Matches.Groups[-4].Value).Replace('&amp;','&')
            'issues' = ('{0}{1}' -f $baseUrl, $_entry.Matches.Groups[-2].Value).Replace('&amp;','&')
        })

        $versions += New-Object -TypeName PSCustomObject -Property $hash
      }

      if ($PSBoundParameters.ContainsKey('SkipEndOfSupportReleases')) {
        $versions | Where-Object { [DateTime]$_.endOfSupportDate -gt (Get-Date) }
      }
      else {
        $versions
      }
    }
    catch {
      throw $_
    }
  }

  end {}
}