#Requires -RunAsAdministrator
#Requires -Version 7.4

param (
    [Parameter(Mandatory=$false)]
    [Switch]$Daemon
)

$splat = @{}

if ($PSBoundParameters.ContainsKey('Daemon')) {
    $splat.Add('Daemon', $true)
}


[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'

Start-PodeServer @splat -ScriptBlock {
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http

    Set-PodeViewEngine -Type Pode

    Add-PodeTimer -Name 'Fetch releases' -Interval 7200 -OnStart -ScriptBlock {
        Lock-PodeObject -ScriptBlock {    
            $cmdletPath = Get-PodeState -Name 'cmdletPath'

            if ($null -eq $cmdletPath) {
                $location = Get-Location | Select-Object -ExpandProperty Path

                $cmdletName = 'Get-AzureLocalRelease.ps1'

                if ($location -eq '/usr/src/app') {
                    $cmdletPath = ('/usr/src/app/{0}' -f $cmdletName)
                }
                else {
                    $cmdletPath = ('../scripts/{0}' -f $cmdletName)        
                }

                Set-PodeState -Name 'cmdletPath' -Value $cmdletPath
                Set-PodeState -Name 'location' -Value $location
            }

            Import-Module -Name $cmdletPath -Force

            try {
                $releases = Get-AzureLocalRelease

                $latestFetchTimestamp = Get-Date
            }
            catch {
                Write-PodeHost ('Releases were not retrievable from the Internet: {0}' -f $_)

                $location = Get-PodeState -Name 'location'

                $releasesPath = if (Test-Path -Path ('{0}/azure-local-releases.json' -f $location)) {
                    ('{0}/azure-local-releases.json' -f $location)
                }
                elseif (Test-Path -Path ('../json/azure-local-releases.json' -f $location)) {
                    ('../json/azure-local-releases.json' -f $location)
                }

                if ($null -ne $releasesPath) {
                    $releases = Get-Content -Path $releasesPath | ConvertFrom-Json
                    $latestFetchTimestamp = Get-Item -Path $releasesPath | Select-Object -ExpandProperty LastWriteTime
                }
            }

            if ($releases -ne $null) {
                Write-PodeHost ('Last fetch timestamp is {0}' -f $latestFetchTimestamp)            

                $latestRelease = $releases | Sort-Object -Property Version -Descending | Select-Object -First 1                          

                Set-PodeState -Name 'latestFetchTimestamp' -Value $latestFetchTimestamp
                Set-PodeState -Name 'releases' -Value $releases
                Set-PodeState -Name 'latestRelease' -Value $latestRelease
            }
            else {
                Write-PodeHost 'Could not retrieve releases from the Internet or local JSON file'
            }
        }
        catch {
            Write-PodeHost $_
        }
    }

    Add-PodeRoute -Method Get -Path '/' -ScriptBlock {
        Lock-PodeObject -ScriptBlock {
            $latestrelease = Get-PodeState -Name 'latestRelease'
            $latestFetchTimestamp = Get-PodeState -Name 'latestFetchTimestamp'
            $response = Get-PodeState -Name 'releases'            

            Write-PodeViewResponse -Path 'index'-Data @{
                'latestRelease' = $latestRelease
                'latestFetchTimestamp' = $latestFetchTimestamp
                'releases' = $response                
            }
        }
    }

    Add-PodeRoute -Method Get -Path '/api/releases' -ScriptBlock {
        Lock-PodeObject -ScriptBlock {
            $response = (Get-PodeState -Name 'releases')

            if ($null -ne $response) {
                if ($null -ne $WebEvent.Query['supported']) {
                    $response = $response | Where-Object { $_.supported -eq [bool]::Parse($WebEvent.Query['supported']) }
                }        

                if ($null -ne $WebEvent.Query['releaseTrain']) {
                    $response = $response | Where-Object { $_.releaseTrain -eq $WebEvent.Query['releaseTrain']}
                }

                if ($null -ne $WebEvent.Query['baselineRelease']) {
                    $response = $response | Where-Object { $_.baselineRelease -eq [bool]::Parse($WebEvent.Query['baselineRelease']) }
                }

                if ($null -ne $WebEvent.Query['buildType']) {
                    $response = $response | Where-Object { $_.buildType -eq $WebEvent.Query['buildType'] }
                }

                if ($null -ne $WebEvent.Query['osBuild']) {
                    $response = $response | Where-Object { $_.osBuild -eq $WebEvent.Query['osBuild'] }
                }                

                if ($null -ne $WebEvent.Query['version']) {
                    $response = $response | Where-Object { $_.version -eq $WebEvent.Query['version'] }
                }                    
                
                if ($null -ne $WebEvent.Query['newDeployments']) {
                    $response = $response | Where-Object { $_.newDeployments -eq [bool]::Parse($WebEvent.Query['newDeployments']) }
                }

                if ($null -ne $WebEvent.Query['solutionUpdate']) {
                    if ([bool]::Parse($WebEvent.Query['solutionUpdate'] -eq $true)) {
                        $response = $response | Where-Object { $_.solutionUpdate.Count -gt 0 }
                    }
                    else {
                        $response = $response | Where-Object { $_.solutionUpdate.Count -eq 0 }
                    } 
                }                

                if ($WebEvent.Query['latest'] -eq $true) {
                    $response = $response | Sort-Object -Property Version -Descending | Select-Object -First 1
                }                

                Write-PodeJsonResponse -Value @{ releases = $response }
            }
        }
    } -PassThru | Set-PodeOARequest -Parameters @(
        (New-PodeOABoolProperty -Name 'supported' -Description "Support status" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'releaseTrain' -Description "A release train, e.g. 2408 or 2411" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOABoolProperty -Name 'baselineRelease' -Description "A baseline releases can be used for new deployments" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'buildType' -Description "A Feature build is the first release in a release train, whereas Cumulative builds are subsequent releases in a release train" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'version' -Description "Full version, e.g. 10.2411.3.2" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'osBuild' -Description "OS Build" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOABoolProperty -Name 'newDeployments' -Description "Retrieve only releases to be used in new deployments" | ConvertTo-PodeOAParameter -In Query)
        (New-PodeOABoolProperty -Name 'solutionUpdate' -Description "Retrieve only releases with downloadable solution update ZIP" | ConvertTo-PodeOAParameter -In Query)
        (New-PodeOABoolProperty -Name 'latest' -Description "Retrieve only the latest release" | ConvertTo-PodeOAParameter -In Query)
    ) -PassThru | Set-PodeOARouteInfo -Summary 'Retrieve Azure Local Releases' -Tags 'Releases'

    Add-PodeRoute -Method Get -Path '/api/releasetrains' -ScriptBlock {
        Lock-PodeObject -ScriptBlock {
            $releases = (Get-PodeState -Name 'releases')

            $releaseTrains = Get-PodeCache -Key 'releaseTrains'

            if ($null -eq $releaseTrains) {
                $uniqueReleaseTrains = ($releases).ReleaseTrain | Sort-Object -Unique

                $response = @()

                foreach ($_releaseTrain in $uniqueReleaseTrains) {
                    $supported = $false

                    foreach ($_release in $releases | Where-Object { $_.ReleaseTrain -eq $_releaseTrain }) {
                        if ($_release.supported) {
                            $supported = $true
                            break
                        }
                    }   

                    $hash = @{
                        'releaseTrain' = $_releaseTrain
                        'supported' = $supported
                    }

                    $response += New-Object -Type PSCustomObject -Property $hash
                }

                $response | Set-PodeCache -Key 'releaseTrains' -Ttl 1800                
            }
            else {
                $response = $releaseTrains
            }      

            if ($null -ne $response) {
                if ($null -ne $WebEvent.Query['supported']) {
                    $response = $response | Where-Object { $_.supported -eq [bool]::Parse($WebEvent.Query['supported']) }
                }        

                if ($null -ne $WebEvent.Query['releaseTrain']) {
                    $response = $response | Where-Object { $_.releaseTrain -eq $WebEvent.Query['releaseTrain']}
                }               
            
                if ($WebEvent.Query['latest'] -eq $true) {
                    $response = $response | Sort-Object -Property ReleaseTrain -Descending | Select-Object -First 1
                }

                Write-PodeJsonResponse -Value @{ releaseTrains = $response }
            }
        }
    } -PassThru | Set-PodeOARequest -Parameters @(
        (New-PodeOABoolProperty -Name 'supported' -Description "Support status" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'releaseTrain' -Description "A release train, e.g. 2408 or 2411" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOABoolProperty -Name 'latest' -Description "Retrieve only the latest release train" | ConvertTo-PodeOAParameter -In Query)
    ) -PassThru | Set-PodeOARouteInfo -Summary 'Retrieve Azure Local Release Trains' -Tags 'ReleaseTrains'    

    Enable-PodeOpenApi -Path '/docs/openapi' -OpenApiVersion 3.1.0 -RouteFilter '/api/*'

    Add-PodeOAInfo -Title 'Azure Local Releases - OpenAPI' -Version 1.0.0 -Description 'API to retrieve information about Azure Local Releases' -ContactUrl 'https://github.com/erikgraa' -ContactName 'erikgraa' -LicenseName MIT

    Add-PodeOATag -Name 'Releases' -Description 'Azure Local Releases' -ExternalDoc $swaggerDocs
    Add-PodeOATag -Name 'ReleaseTrains' -Description 'Azure Local Release Trains' -ExternalDoc $swaggerDocs    

    Enable-PodeOAViewer -Type Swagger -Path '/docs/swagger'
}