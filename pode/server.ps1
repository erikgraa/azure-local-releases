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

    Set-PodeCacheDefaultTtl -Value 3600

    Add-PodeStaticRoute -Path '/' -Source './' -Defaults @('index.html')

    Add-PodeTimer -Name 'Fetch releases' -Interval 7200 -OnStart -ScriptBlock {
        Lock-PodeObject -ScriptBlock {
            $location = Get-PodeCache -Key 'location'

            if ($null -eq $location) {           
                Get-Location | Select-Object -ExpandProperty Path | Set-PodeCache -Key 'location' -Ttl 0

                $cmdletName = 'Get-AzureLocalRelease.ps1'

                try {
                    if ($location -eq '/usr/src/app') {
                        $cmdlet = ('/usr/src/app/{0}' -f $cmdletName)
                    }
                    else {
                        $cmdlet = ('../scripts/{0}' -f $cmdletName)        
                    }      

                    Import-Module -Name $cmdlet
                }
                catch {
                    Write-Host ("Cannot find cmdlet '{0}'" -f $cmdletName)
                }
            }

            $releases = Get-AzureLocalRelease

            Write-Host "Fetched releases"
   
            $state:releases = $releases
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
                    $response = $response | Where-Object { $_.BuildType -eq $WebEvent.Query['buildType'] }
                }

                if ($null -ne $WebEvent.Query['version']) {
                    $response = $response | Where-Object { $_.Version -eq $WebEvent.Query['version'] }
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
                    $supported = if ((-not($releases | Where-Object { $_.ReleaseTrain -eq $_releaseTrain }).supported.Contains($true))) {
                        $false
                    }
                    else {
                        $true
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