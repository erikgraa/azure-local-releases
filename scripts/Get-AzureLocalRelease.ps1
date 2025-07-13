<#PSScriptInfo
  .VERSION 1.1
  .GUID 082911ff-1d75-4cbc-9391-ab093db0aaab
  .AUTHOR erikgraa
#>

<#

  .DESCRIPTION
  Script to enumerate Azure Local releases.

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
    try {
      $baseUrl = $Uri.ToString().Substring(0, $Uri.ToString().Length-$Uri.ToString().Split('/')[-1].Length)

      $documentation = Invoke-RestMethod -Uri $uri

      $solutionUpdateUri = 'https://raw.githubusercontent.com/MicrosoftDocs/azure-stack-docs/refs/heads/main/azure-local/update/import-discover-updates-offline-23h2.md'

      $solutionUpdatePattern = "\[(.*?)\].*?(https:\/\/.*?.zip).*?\|(.*?)\|"

      $solutionUpdateContent = Invoke-RestMethod -Uri $solutionUpdateUri

      $solutionUpdate = (Select-String -InputObject $solutionUpdateContent -Pattern $solutionUpdatePattern -AllMatches)

      $solutionUpdateHash = @{}

      $i = 0
      
      while ($i -lt $solutionUpdate.Matches.Groups.Count-1) {   
        $solutionUpdateHash.Add($solutionUpdate.Matches.Groups[$i+1].Value.Trim(), @{
          'uri' = $solutionUpdate.Matches.Groups[$i+2].Value.Trim()
          'fileHash' = $solutionUpdate.Matches.Groups[$i+3].Value.Trim()
        })

        $i+= 4
      }


      # ISO 8601
      $tablePattern = "(?ms)<tr>\n<td>\d+\.\d+\.\d+\.\d+.*?Availability date.*?<\/td>\n<\/tr>"

      $entryPattern = '(?ms)<tr>\n<td>(\d+\.\d+\.\d+\.\d+)\s+.*?<br><br>\s+Availability date:\s+(\d{4,4}-\d{2,2}-\d{2,2})<\/td>\n<td>(\d+.\d+)<\/td>\n<td><a href="(.+?)".*?>((\w+) OS security update)<\/a><\/td>\n<td><a href="(.+?)".*?>(Features and improvements)<\/a><\/td>\n<td><a href="(.+?)".*?>(Known issues)<\/a><\/td>\n(<td>Not applicable<\/td>\n|<td><a href="(.+\.zip)".*SHA256: (.*?)<\/td>\n)?<\/tr>'

      $table = (Select-String -InputObject $documentation -Pattern $tablePattern -AllMatches).Matches.Groups

      #$newDeploymentsPattern = '(?ms)<section id="tabpanel_1_new-deployments".*?<\/section>'
      $newDeploymentsPattern = '(?ms)<section id="tabpanel_1_OS-build-26100-xxxx".*?<\/section>'
      
      $newDeployments = (Select-String -InputObject $documentation -Pattern $newDeploymentsPattern).matches.value

      #$existingDeploymentsPattern = '(?ms)<section id="tabpanel_1_existing-deployments".*?<\/section>'
      $existingDeploymentsPattern = '(?ms)<section id="tabpanel_1_OS-build-25398-xxxx".*?<\/section>'

      $existingDeployments = (Select-String -InputObject $documentation -Pattern $existingDeploymentsPattern).matches.value

      if ($null -eq $table) {
        throw ('No releases found at {0}, format or URL may have changed' -f $Uri)
      }

      $versions = @()

      for($i=$table.Length-1; $i -ge 0; $i--) {
        $_entry = Select-String -Pattern $entryPattern -InputObject $table[$i].Value

        $fullVersionString = $_entry.Matches.Groups[1].Value
        $fullVersion = [version]$fullVersionString

        # Releases after 2408.0 are "baseline releases"
        $baselineReleaseThreshold = [version]'10.2408.0.0'

        # Only releases after 2411.3 have cumulative SU ZIPs
        $SUThreshold = [version]'10.2411.3.0'

        $baselineRelease = if ($fullVersion -ge $baselineReleaseThreshold) {
            $true
        }
        else {
            $false
        }

        $newDeployment = if ($newDeployments -match $_entry.Matches.Groups[1].Value) {
          $true
        }
        else {
          $false
        }

        $existingDeployment = if ($existingDeployments -match $_entry.Matches.Groups[1].Value) {
          $true
        }
        else {
          $false
        }
        
        $oldVersion = if ($newDeployments -eq $false -and $existingDeployment -eq $false) {
          $true
        }
        else {
          $false
        }

        $solutionUpdate = if ($fullversion -ge $SUThreshold -and $solutionupdateHash.ContainsKey($fullVersionString)) {
          [Ordered]@{
            'uri' = $solutionupdateHash.Get_Item($fullVersionString).uri
            'fileHash' = $solutionupdateHash.Get_Item($fullVersionString).fileHash
          }
        }
        else {
          @{}
        }

        # The first release of a release train is a feature build. Any subsequent release within a release train is a cumulative update build.
        # After the 2503 release it's not really possible to determine this with accuracy programmatically. The next feature update is 2510.
        <# $buildType = if ($null -eq ($versions | Where-Object { $_.releaseTrain -eq $_entry.Matches.Groups[1].Value.Split('.')[1] })) {
          'Feature'
        }
        else {
          'Cumulative'
        }#>

        if ($OutputType -eq 'String') {
          $fullVersion = $fullVersion.ToString()
        }    

        $hash = [Ordered]@{}

        $release = ('{0}.{1}.{2}' -f $_entry.Matches.Groups[1].Value.Split('.')[1], $_entry.Matches.Groups[1].Value.Split('.')[2], $_entry.Matches.Groups[1].Value.Split('.')[3])
        $releaseShortened = ('{0}.{1}' -f $_entry.Matches.Groups[1].Value.Split('.')[1], $_entry.Matches.Groups[1].Value.Split('.')[2])

        $endOfSupportDate = (Get-Date -Date ([DateTime]$_entry.Matches.Groups[2].Value).AddDays(180) -UFormat '%Y-%m-%d')

        $supported = if ([DateTime]::Now -le $endOfSupportDate) {
            $true
        }
        else {
            $false
        }

        $hash.Add('version', $fullVersion)
        $hash.Add('availabilityDate', $_entry.Matches.Groups[2].Value)
        $hash.Add('newDeployments', $newDeployment)
        $hash.Add('osBuild', $_entry.Matches.Groups[3].Value)
        $hash.Add('releaseTrain', $_entry.Matches.Groups[1].Value.Split('.')[1])
        $hash.Add('release', $release)
        $hash.Add('releaseShortened', $releaseShortened)
        $hash.Add('baselineRelease', $baselineRelease)
        #$hash.Add('buildType', $buildType)
        $hash.Add('endOfSupportDate', (Get-Date -Date ([DateTime]$_entry.Matches.Groups[2].Value).AddDays(180) -UFormat '%Y-%m-%d'))
        $hash.add('supported', $supported)
        $hash.Add('solutionUpdate', $solutionUpdate)
        $hash.Add('urls', [Ordered]@{
            'security' = ('{0}{1}' -f $baseUrl, (($_entry).Matches.Groups | Where-Object { $_.Value -match '^security-update' }).Value.Replace('&amp;','&'))
            'news' = ('{0}{1}' -f $baseUrl, (($_entry).Matches.Groups | Where-Object { $_.Value -match '^whats-new?' }).Value.Replace('&amp;','&'))
            'issues' = ('{0}{1}' -f $baseUrl, (($_entry).Matches.Groups | Where-Object { $_.Value -match '^known-issues?' }).Value.Replace('&amp;','&'))
        })

        $versions += New-Object -TypeName PSCustomObject -Property $hash
      }

      if ($PSBoundParameters.ContainsKey('SupportedReleases')) {
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