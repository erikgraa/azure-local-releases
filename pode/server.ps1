[System.Threading.Thread]::CurrentThread.CurrentUICulture = 'en-US'

Start-PodeServer {
    Add-PodeEndpoint -Address * -Port 8080 -Protocol Http

    Set-PodeCacheDefaultTtl -Value 3600

    Add-PodeStaticRoute -Path '/' -Source './' -Defaults @('index.html')    

    Add-PodeRoute -Method Get -Path '/api/releases' -ScriptBlock {
        $releases = Get-PodeCache -Key 'releases'

        if ($null -eq $releases) {
            $location = Get-Location | Select-Object -ExpandProperty Path
            if ($location -eq '/') {
                . /usr/src/app/Get-AzureLocalRelease.ps1
            }
            else {
                . ../scripts/Get-AzureLocalRelease.ps1        
            }

            $releases = Get-AzureLocalRelease    

            Write-Host "Cached"

            $releases | Set-PodeCache -Key 'releases' -Ttl 7200            
        }

        $response = $releases

        if ($null -ne $WebEvent.Query['endOfSupport']) {
            $response = $response | Where-Object { $_.endOfSupport -eq [bool]::Parse($WebEvent.Query['endOfSupport']) }
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
    } -PassThru | Set-PodeOARequest -Parameters @(
        (New-PodeOABoolProperty -Name 'endOfSupport' -Description "End-of-support status" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'releaseTrain' -Description "A release train, e.g. 2408 or 2411" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOABoolProperty -Name 'baselineRelease' -Description "A baseline releases can be used for new deployments" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'buildType' -Description "A Feature build is the first release in a release train, whereas Cumulative builds are subsequent releases in a release train" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOAStringProperty -Name 'version' -Description "Full version, e.g. 10.2411.3.2" | ConvertTo-PodeOAParameter -In Query),
        (New-PodeOABoolProperty -Name 'latest' -Description "Retrieve only the latest release" | ConvertTo-PodeOAParameter -In Query)
    ) -PassThru | Set-PodeOARouteInfo -Summary 'Retrieve Azure Local releases' -Tags 'Releases'

    Enable-PodeOpenApi -Path '/docs/openapi' -OpenApiVersion 3.1.0 -RouteFilter '/api/*'

    Add-PodeOAInfo -Title 'Azure Local Releases - OpenAPI' -Version 1.0.0 -Description 'API to retrieve Azure Local Releases' -ContactUrl 'https://github.com/erikgraa' -ContactName 'erikgraa' -LicenseName MIT

    Add-PodeOATag -Name 'Releases' -Description 'Azure Local Releases' -ExternalDoc $swaggerDocs    

    Enable-PodeOAViewer -Type Swagger -Path '/docs/swagger'
}