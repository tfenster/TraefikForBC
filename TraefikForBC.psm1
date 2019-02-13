function Initialize-TraefikForBC {
    param
    (
        [parameter(Mandatory=$true)]
        [String]
        $email,

        [parameter(Mandatory=$true)]
        [String]
        $externaldns
    )
    Write-Host "Create folder structure at c:\traefikforbc"
    mkdir c:\traefikforbc
    mkdir c:\traefikforbc\my
    mkdir c:\traefikforbc\config
    New-Item -Path c:\traefikforbc\config\acme.json

    Write-Host "Pull traefik image"
    docker pull stefanscherer/traefik-windows

    Write-Host "Create traefik config file"
    $template = Get-Content 'template_traefik.toml' -Raw
    $expanded = Invoke-Expression "@`"`r`n$template`r`n`"@"
    $expanded | Out-File "c:\traefikforbc\config\traefik.toml" -Encoding ASCII

    Write-Host "Copy heathcheck"
    Copy-Item -Path .\CheckHealth.ps1 -Destination "c:\traefikforbc\my"
    
    Write-Host "Install navcontainerhelper"
    install-module navcontainerhelper -force
}
Export-ModuleMember -Function Initialize-TraefikForBC
    
function Start-Traefik {
    docker run -p 8080:8080 -p 443:443 -p 80:80 -d -v c:/traefikforbc/config:c:/etc/traefik -v \\.\pipe\docker_engine:\\.\pipe\docker_engine stefanscherer/traefik-windows --docker.endpoint=npipe:////./pipe/docker_engine
}
Export-ModuleMember -Function Start-Traefik


function Start-BCWithTraefikLabels {
    param
    (
        [parameter(Mandatory=$true,Position=0)]
        [String]
        $name,

        [parameter(Mandatory=$true,Position=1)]
        [String]
        $image,

        [parameter(Mandatory=$true,Position=1)]
        [String]
        $externaldns,

        [parameter(Mandatory=$false)]
        [Switch]
        $WhatIf
    )

    $restPart = "/${name}rest/" 
    $soapPart = "/${name}soap/"
    $devPart = "/${name}dev/"
    $dlPart = "/${name}dl/"
    $webclientPart = "/$name/"
    $baseUrl = "https://$externaldns"
    $restUrl = $baseUrl + $restPart
    $soapUrl = $baseUrl + $soapPart
    $webclientUrl = $baseUrl + $webclientPart

    $customNavSettings = "customnavsettings=PublicODataBaseUrl=$restUrl,PublicSOAPBaseUrl=$soapUrl,PublicWebBaseUrl=$webclientUrl"
    $webclientRule="PathPrefix:$webclientPart"
    $soapRule="PathPrefix:${soapPart};ReplacePathRegex: ^${soapPart}(.*) /NAV/WS/`$1"
    $restRule="PathPrefix:${restPart};ReplacePathRegex: ^${restPart}(.*) /NAV/OData/`$1"
    $devRule="PathPrefix:${devPart};ReplacePathRegex: ^${devPart}(.*) /NAV/`$1"
    $dlRule="PathPrefixStrip:${dlPart}"

    $additionalParameters = @("--hostname $externaldns",
                #"-v c:\traefikforbc\my:c:\run\my",
                "-e webserverinstance=$name",
                "-e publicdnsname=$externaldns", 
                "-e $customNavSettings",
                "-l `"traefik.web.frontend.rule=$webclientRule`"", 
                "-l `"traefik.web.port=80`"",
                "-l `"traefik.soap.frontend.rule=$soapRule`"", 
                "-l `"traefik.soap.port=7047`"",
                "-l `"traefik.rest.frontend.rule=$restRule`"", 
                "-l `"traefik.rest.port=7048`"",
                "-l `"traefik.dev.frontend.rule=$devRule`"", 
                "-l `"traefik.dev.port=7049`"",
                "-l `"traefik.dl.frontend.rule=$dlRule`"", 
                "-l `"traefik.dl.port=8080`"",
                "-l `"traefik.enable=true`"",
                "-l `"traefik.frontend.entryPoints=https`""
    )
    New-NavContainer -accept_eula `
                 -containerName $name `
                 -imageName $image `
                 -additionalParameters $additionalParameters `
                 -myScripts @("c:\traefikforbc\my\CheckHealth.ps1")
}
Export-ModuleMember -Function Start-BCWithTraefikLabels
