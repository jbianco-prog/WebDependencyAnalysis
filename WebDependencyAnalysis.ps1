## -
## - Downloaded from micro-one.com
## - Operational Security
## -
## - Web Dependency Analyzer (v.2.à Augmented by Ai)
## - PowerShell script to analyze and visualize all HTTP/HTTPS dependencies of a web page
## - Creation date        :: 10/10/2008
## - Last update on       :: 16/10/2025
## - Author               :: Micro-one (contact@micro-one.com)
## -
## ------

##
## ============================================================================
## CONFIGURATION - Edit these variables to customize the script
## ============================================================================
##

## --
## Analysis Configuration
## --
param(
    [Parameter(Mandatory=$false)]
    [string]$TargetURL = "",                    # Target URL to analyze (can be provided as parameter)
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFormat = "both",             # Output format: text, html, mermaid, graphviz, json, both (text+html)
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFolder = ".\WebAnalysis"     # Output folder for results
)

## --
## Advanced Options
## --
$maxDepth = 1                                   # Recursion depth (1 = only direct dependencies)
$followRedirects = $true                        # Follow HTTP redirects
$timeoutSeconds = 30                            # Request timeout (seconds)
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"  # User agent string
$includeDataURIs = $false                       # Include data: URIs in analysis
$checkSSL = $true                               # Check SSL certificate validity

## --
## Filtering Options
## --
$includeExternal = $true                        # Include external domains
$includeCDN = $true                             # Include CDN resources
$includeInline = $true                          # Include inline scripts/styles

## --
## Display Options
## --
$showProgress = $true                           # Show progress during analysis
$colorOutput = $true                            # Use colored console output
$verboseOutput = $false                         # Show detailed information

##
## ============================================================================
## END OF CONFIGURATION
## ============================================================================
##

## --
## Set TLS 1.2
## --
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

## --
## Global variables
## --
$global:discoveredURLs = @{}
$global:urlsByType = @{
    HTML = @()
    CSS = @()
    JavaScript = @()
    Image = @()
    Font = @()
    Media = @()
    AJAX = @()
    Other = @()
}
$global:stats = @{
    TotalRequests = 0
    SuccessfulRequests = 0
    FailedRequests = 0
    TotalSize = 0
    UniqueDomains = @()
}

## --
## Function to display banner
## --
function Show-Banner {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  Web Dependency Analyzer v1.0" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
}

## --
## Function to normalize URL
## --
function Get-NormalizedURL {
    param(
        [string]$URL,
        [string]$BaseURL
    )
    
    try {
        # Skip data URIs
        if ($URL.StartsWith("data:")) {
            if ($includeDataURIs) {
                return $URL
            }
            return $null
        }
        
        # Skip javascript: and mailto:
        if ($URL.StartsWith("javascript:") -or $URL.StartsWith("mailto:") -or $URL.StartsWith("#")) {
            return $null
        }
        
        # Handle protocol-relative URLs
        if ($URL.StartsWith("//")) {
            $baseUri = [System.Uri]$BaseURL
            $URL = "$($baseUri.Scheme):$URL"
        }
        
        # Handle relative URLs
        if (-not $URL.StartsWith("http")) {
            $baseUri = [System.Uri]$BaseURL
            $absoluteUri = New-Object System.Uri($baseUri, $URL)
            return $absoluteUri.AbsoluteUri
        }
        
        return $URL
    } catch {
        return $null
    }
}

## --
## Function to determine resource type
## --
function Get-ResourceType {
    param([string]$URL)
    
    $extension = [System.IO.Path]::GetExtension($URL).ToLower()
    
    switch -Regex ($extension) {
        '\.(jpg|jpeg|png|gif|bmp|webp|svg|ico)$' { return "Image" }
        '\.(css)$' { return "CSS" }
        '\.(js)$' { return "JavaScript" }
        '\.(woff|woff2|ttf|eot|otf)$' { return "Font" }
        '\.(mp4|webm|ogg|mp3|wav)$' { return "Media" }
        '\.(json|xml)$' { return "AJAX" }
        '\.(html|htm|php|asp|aspx)$' { return "HTML" }
        default { return "Other" }
    }
}

## --
## Function to extract domain
## --
function Get-DomainFromURL {
    param([string]$URL)
    
    try {
        $uri = [System.Uri]$URL
        return $uri.Host
    } catch {
        return "unknown"
    }
}

## --
## Function to format file size
## --
function Format-FileSize {
    param([long]$Size)
    
    if ($Size -gt 1MB) {
        return "{0:N2} MB" -f ($Size / 1MB)
    } elseif ($Size -gt 1KB) {
        return "{0:N2} KB" -f ($Size / 1KB)
    } else {
        return "$Size bytes"
    }
}

## --
## Function to analyze HTML content
## --
function Get-HTMLDependencies {
    param(
        [string]$URL,
        [string]$Content
    )
    
    $dependencies = @()
    
    try {
        # Parse HTML
        $html = New-Object -ComObject "HTMLFile"
        
        # Different methods for different PowerShell versions
        try {
            $html.IHTMLDocument2_write($Content)
        } catch {
            $html.write([System.Text.Encoding]::Unicode.GetBytes($Content))
        }
        
        # Extract links (CSS, canonical, etc.)
        $links = $html.getElementsByTagName("link")
        foreach ($link in $links) {
            $href = $link.href
            if ($href) {
                $normalizedURL = Get-NormalizedURL -URL $href -BaseURL $URL
                if ($normalizedURL) {
                    $dependencies += @{
                        URL = $normalizedURL
                        Type = $(if ($link.rel -match "stylesheet") { "CSS" } else { "Other" })
                        Source = "link"
                    }
                }
            }
        }
        
        # Extract scripts
        $scripts = $html.getElementsByTagName("script")
        foreach ($script in $scripts) {
            $src = $script.src
            if ($src) {
                $normalizedURL = Get-NormalizedURL -URL $src -BaseURL $URL
                if ($normalizedURL) {
                    $dependencies += @{
                        URL = $normalizedURL
                        Type = "JavaScript"
                        Source = "script"
                    }
                }
            }
        }
        
        # Extract images
        $images = $html.getElementsByTagName("img")
        foreach ($img in $images) {
            $src = $img.src
            if ($src) {
                $normalizedURL = Get-NormalizedURL -URL $src -BaseURL $URL
                if ($normalizedURL) {
                    $dependencies += @{
                        URL = $normalizedURL
                        Type = "Image"
                        Source = "img"
                    }
                }
            }
        }
        
        # Extract iframes
        $iframes = $html.getElementsByTagName("iframe")
        foreach ($iframe in $iframes) {
            $src = $iframe.src
            if ($src) {
                $normalizedURL = Get-NormalizedURL -URL $src -BaseURL $URL
                if ($normalizedURL) {
                    $dependencies += @{
                        URL = $normalizedURL
                        Type = "HTML"
                        Source = "iframe"
                    }
                }
            }
        }
        
    } catch {
        Write-Warning "HTML parsing failed, using regex fallback"
        
        # Fallback to regex parsing
        # CSS links
        $cssMatches = [regex]::Matches($Content, '<link[^>]+href=["'']([^"'']+)["''][^>]*>')
        foreach ($match in $cssMatches) {
            $href = $match.Groups[1].Value
            $normalizedURL = Get-NormalizedURL -URL $href -BaseURL $URL
            if ($normalizedURL) {
                $dependencies += @{
                    URL = $normalizedURL
                    Type = "CSS"
                    Source = "link"
                }
            }
        }
        
        # JavaScript
        $jsMatches = [regex]::Matches($Content, '<script[^>]+src=["'']([^"'']+)["'']')
        foreach ($match in $jsMatches) {
            $src = $match.Groups[1].Value
            $normalizedURL = Get-NormalizedURL -URL $src -BaseURL $URL
            if ($normalizedURL) {
                $dependencies += @{
                    URL = $normalizedURL
                    Type = "JavaScript"
                    Source = "script"
                }
            }
        }
        
        # Images
        $imgMatches = [regex]::Matches($Content, '<img[^>]+src=["'']([^"'']+)["'']')
        foreach ($match in $imgMatches) {
            $src = $match.Groups[1].Value
            $normalizedURL = Get-NormalizedURL -URL $src -BaseURL $URL
            if ($normalizedURL) {
                $dependencies += @{
                    URL = $normalizedURL
                    Type = "Image"
                    Source = "img"
                }
            }
        }
    }
    
    return $dependencies
}

## --
## Function to analyze CSS content
## --
function Get-CSSDependencies {
    param(
        [string]$URL,
        [string]$Content
    )
    
    $dependencies = @()
    
    # Extract @import
    $importMatches = [regex]::Matches($Content, '@import\s+(?:url\()?["'']?([^"''\)]+)["'']?\)?')
    foreach ($match in $importMatches) {
        $href = $match.Groups[1].Value
        $normalizedURL = Get-NormalizedURL -URL $href -BaseURL $URL
        if ($normalizedURL) {
            $dependencies += @{
                URL = $normalizedURL
                Type = "CSS"
                Source = "@import"
            }
        }
    }
    
    # Extract url() references
    $urlMatches = [regex]::Matches($Content, 'url\(["'']?([^"''\)]+)["'']?\)')
    foreach ($match in $urlMatches) {
        $href = $match.Groups[1].Value
        $normalizedURL = Get-NormalizedURL -URL $href -BaseURL $URL
        if ($normalizedURL) {
            $type = Get-ResourceType -URL $normalizedURL
            $dependencies += @{
                URL = $normalizedURL
                Type = $type
                Source = "url()"
            }
        }
    }
    
    return $dependencies
}

## --
## Function to fetch and analyze URL
## --
function Get-URLDependencies {
    param(
        [string]$URL,
        [int]$Depth = 0
    )
    
    # Skip if already processed
    if ($global:discoveredURLs.ContainsKey($URL)) {
        return
    }
    
    # Mark as discovered
    $global:discoveredURLs[$URL] = @{
        Depth = $Depth
        Type = Get-ResourceType -URL $URL
        Status = "Pending"
        Size = 0
        Dependencies = @()
    }
    
    $global:stats.TotalRequests++
    
    try {
        if ($showProgress) {
            Write-Host "  [$Depth] Fetching: $URL" -ForegroundColor Cyan
        }
        
        # Fetch resource
        $response = Invoke-WebRequest -Uri $URL -UserAgent $userAgent -TimeoutSec $timeoutSeconds -ErrorAction Stop
        
        $global:stats.SuccessfulRequests++
        $contentLength = 0
        
        if ($response.Headers.'Content-Length') {
            $contentLength = [long]$response.Headers.'Content-Length'[0]
        } else {
            $contentLength = $response.Content.Length
        }
        
        $global:stats.TotalSize += $contentLength
        
        # Update discovery info
        $global:discoveredURLs[$URL].Status = "Success"
        $global:discoveredURLs[$URL].Size = $contentLength
        $global:discoveredURLs[$URL].StatusCode = $response.StatusCode
        $global:discoveredURLs[$URL].ContentType = $response.Headers.'Content-Type'
        
        # Track unique domains
        $domain = Get-DomainFromURL -URL $URL
        if ($domain -notin $global:stats.UniqueDomains) {
            $global:stats.UniqueDomains += $domain
        }
        
        # Add to type category
        $resourceType = $global:discoveredURLs[$URL].Type
        if ($global:urlsByType.ContainsKey($resourceType)) {
            $global:urlsByType[$resourceType] += $URL
        }
        
        if ($showProgress) {
            Write-Host "    -> Success ($(Format-FileSize $contentLength))" -ForegroundColor Green
        }
        
        # Parse dependencies if within depth limit
        if ($Depth -lt $maxDepth) {
            $dependencies = @()
            
            $contentType = $response.Headers.'Content-Type'
            
            if ($contentType -match "text/html") {
                $dependencies = Get-HTMLDependencies -URL $URL -Content $response.Content
            } elseif ($contentType -match "text/css") {
                $dependencies = Get-CSSDependencies -URL $URL -Content $response.Content
            }
            
            $global:discoveredURLs[$URL].Dependencies = $dependencies
            
            # Recursively fetch dependencies
            foreach ($dep in $dependencies) {
                Get-URLDependencies -URL $dep.URL -Depth ($Depth + 1)
            }
        }
        
    } catch {
        $global:stats.FailedRequests++
        $global:discoveredURLs[$URL].Status = "Failed"
        $global:discoveredURLs[$URL].Error = $_.Exception.Message
        
        if ($showProgress) {
            Write-Host "    -> Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

## --
## Function to generate text report
## --
function Export-TextReport {
    param([string]$OutputFile)
    
    $report = @"
============================================
  Web Dependency Analysis Report
============================================

Target URL: $TargetURL
Analysis Date: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")

============================================
  STATISTICS
============================================

Total Requests      : $($global:stats.TotalRequests)
Successful          : $($global:stats.SuccessfulRequests)
Failed              : $($global:stats.FailedRequests)
Total Size          : $(Format-FileSize $global:stats.TotalSize)
Unique Domains      : $($global:stats.UniqueDomains.Count)

============================================
  RESOURCES BY TYPE
============================================

"@
    
    foreach ($type in $global:urlsByType.Keys | Sort-Object) {
        $count = $global:urlsByType[$type].Count
        if ($count -gt 0) {
            $report += "`n$type : $count resources`n"
            $report += "-" * 40 + "`n"
            foreach ($url in $global:urlsByType[$type]) {
                $info = $global:discoveredURLs[$url]
                $size = if ($info.Size -gt 0) { Format-FileSize $info.Size } else { "N/A" }
                $report += "  - $url ($size)`n"
            }
        }
    }
    
    $report += "`n============================================`n"
    $report += "  UNIQUE DOMAINS`n"
    $report += "============================================`n`n"
    
    foreach ($domain in $global:stats.UniqueDomains | Sort-Object) {
        $report += "  - $domain`n"
    }
    
    $report | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "[+] Text report saved: $OutputFile" -ForegroundColor Green
}

## --
## Function to generate HTML report
## --
function Export-HTMLReport {
    param([string]$OutputFile)
    
    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Dependency Analysis - $TargetURL</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        .header p {
            opacity: 0.9;
            font-size: 1.1em;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            padding: 30px;
            background: #f8f9fa;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        .stat-card h3 {
            color: #667eea;
            font-size: 0.9em;
            text-transform: uppercase;
            margin-bottom: 10px;
        }
        .stat-card p {
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }
        .content {
            padding: 30px;
        }
        .section {
            margin-bottom: 30px;
        }
        .section h2 {
            color: #667eea;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #667eea;
        }
        .resource-type {
            margin-bottom: 20px;
        }
        .resource-type h3 {
            color: #764ba2;
            margin-bottom: 10px;
            font-size: 1.2em;
        }
        .resource-list {
            background: #f8f9fa;
            border-radius: 5px;
            padding: 15px;
        }
        .resource-item {
            padding: 10px;
            margin-bottom: 5px;
            background: white;
            border-radius: 4px;
            border-left: 4px solid #667eea;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
            word-break: break-all;
        }
        .resource-item .size {
            float: right;
            color: #666;
            font-weight: bold;
        }
        .domain-list {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }
        .domain-badge {
            background: #667eea;
            color: white;
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 0.9em;
        }
        .tree {
            font-family: monospace;
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 20px;
            border-radius: 5px;
            overflow-x: auto;
        }
        .tree-item {
            padding: 2px 0;
        }
        .tree-item.success { color: #4ec9b0; }
        .tree-item.failed { color: #f48771; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔍 Web Dependency Analysis</h1>
            <p>$TargetURL</p>
            <p style="font-size: 0.9em; opacity: 0.8;">Generated on $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h3>Total Requests</h3>
                <p>$($global:stats.TotalRequests)</p>
            </div>
            <div class="stat-card">
                <h3>Successful</h3>
                <p style="color: #28a745;">$($global:stats.SuccessfulRequests)</p>
            </div>
            <div class="stat-card">
                <h3>Failed</h3>
                <p style="color: #dc3545;">$($global:stats.FailedRequests)</p>
            </div>
            <div class="stat-card">
                <h3>Total Size</h3>
                <p>$(Format-FileSize $global:stats.TotalSize)</p>
            </div>
            <div class="stat-card">
                <h3>Unique Domains</h3>
                <p>$($global:stats.UniqueDomains.Count)</p>
            </div>
        </div>
        
        <div class="content">
            <div class="section">
                <h2>📦 Resources by Type</h2>
"@
    
    foreach ($type in $global:urlsByType.Keys | Sort-Object) {
        $count = $global:urlsByType[$type].Count
        if ($count -gt 0) {
            $html += @"
                <div class="resource-type">
                    <h3>$type ($count)</h3>
                    <div class="resource-list">
"@
            foreach ($url in $global:urlsByType[$type]) {
                $info = $global:discoveredURLs[$url]
                $size = if ($info.Size -gt 0) { Format-FileSize $info.Size } else { "" }
                $sizeHtml = if ($size) { "<span class='size'>$size</span>" } else { "" }
                $html += "                        <div class='resource-item'>$sizeHtml$url</div>`n"
            }
            $html += @"
                    </div>
                </div>
"@
        }
    }
    
    $html += @"
            </div>
            
            <div class="section">
                <h2>🌐 Unique Domains</h2>
                <div class="domain-list">
"@
    
    foreach ($domain in $global:stats.UniqueDomains | Sort-Object) {
        $html += "                    <span class='domain-badge'>$domain</span>`n"
    }
    
    $html += @"
                </div>
            </div>
        </div>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "[+] HTML report saved: $OutputFile" -ForegroundColor Green
}

## --
## Function to generate Mermaid diagram
## --
function Export-MermaidDiagram {
    param([string]$OutputFile)
    
    $mermaid = "graph TD`n"
    $mermaid += "    Start[`"$TargetURL`"]:::main`n"
    
    $nodeId = 0
    $nodeMap = @{}
    
    foreach ($url in $global:discoveredURLs.Keys) {
        $nodeId++
        $nodeMap[$url] = "node$nodeId"
        $type = $global:discoveredURLs[$url].Type
        $status = $global:discoveredURLs[$url].Status
        
        $label = ([System.Uri]$url).PathAndQuery
        if ($label.Length -gt 40) {
            $label = $label.Substring(0, 37) + "..."
        }
        
        $class = switch ($type) {
            "CSS" { "css" }
            "JavaScript" { "js" }
            "Image" { "img" }
            "Font" { "font" }
            default { "other" }
        }
        
        if ($status -eq "Failed") {
            $class = "failed"
        }
        
        $mermaid += "    $($nodeMap[$url])[`"$label`"]:::$class`n"
    }
    
    # Add connections
    foreach ($url in $global:discoveredURLs.Keys) {
        $deps = $global:discoveredURLs[$url].Dependencies
        if ($deps.Count -gt 0) {
            foreach ($dep in $deps) {
                $depURL = $dep.URL
                if ($nodeMap.ContainsKey($depURL)) {
                    $mermaid += "    $($nodeMap[$url]) --> $($nodeMap[$depURL])`n"
                }
            }
        } elseif ($url -eq $TargetURL) {
            # Main URL connections
            foreach ($depUrl in $global:discoveredURLs.Keys) {
                if ($depUrl -ne $TargetURL -and $global:discoveredURLs[$depUrl].Depth -eq 1) {
                    $mermaid += "    Start --> $($nodeMap[$depUrl])`n"
                }
            }
        }
    }
    
    # Add styles
    $mermaid += "`n    classDef main fill:#667eea,stroke:#764ba2,stroke-width:3px,color:#fff`n"
    $mermaid += "    classDef css fill:#264de4,stroke:#1b3ba3,color:#fff`n"
    $mermaid += "    classDef js fill:#f0db4f,stroke:#c7b929,color:#000`n"
    $mermaid += "    classDef img fill:#7ed956,stroke:#5fa73c,color:#000`n"
    $mermaid += "    classDef font fill:#e67e22,stroke:#bf6516,color:#fff`n"
    $mermaid += "    classDef failed fill:#dc3545,stroke:#a71d2a,color:#fff`n"
    $mermaid += "    classDef other fill:#95a5a6,stroke:#7f8c8d,color:#fff`n"
    
    $mermaid | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "[+] Mermaid diagram saved: $OutputFile" -ForegroundColor Green
    Write-Host "    View at: https://mermaid.live/" -ForegroundColor Yellow
}

## --
## Function to generate JSON export
## --
function Export-JSONReport {
    param([string]$OutputFile)
    
    $jsonData = @{
        targetURL = $TargetURL
        analysisDate = (Get-Date -Format "o")
        statistics = $global:stats
        resourcesByType = $global:urlsByType
        allResources = $global:discoveredURLs
    }
    
    $jsonData | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "[+] JSON export saved: $OutputFile" -ForegroundColor Green
}

## --
## Main execution
## --
try {
    Show-Banner
    
    # Prompt for URL if not provided
    if ([string]::IsNullOrWhiteSpace($TargetURL)) {
        $TargetURL = Read-Host "Enter the URL to analyze"
    }
    
    # Validate URL
    if (-not $TargetURL.StartsWith("http")) {
        throw "Invalid URL. Must start with http:// or https://"
    }
    
    Write-Host "Target URL    : " -NoNewline -ForegroundColor Yellow
    Write-Host $TargetURL -ForegroundColor White
    Write-Host "Output Folder : " -NoNewline -ForegroundColor Yellow
    Write-Host $OutputFolder -ForegroundColor White
    Write-Host ""
    
    # Create output folder
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    
    # Start analysis
    Write-Host "[*] Starting dependency analysis..." -ForegroundColor Cyan
    Write-Host ""
    
    $analysisStart = Get-Date
    Get-URLDependencies -URL $TargetURL -Depth 0
    $analysisDuration = (Get-Date) - $analysisStart
    
    Write-Host ""
    Write-Host "[*] Analysis complete!" -ForegroundColor Green
    Write-Host "    Duration: $($analysisDuration.TotalSeconds) seconds" -ForegroundColor Gray
    Write-Host ""
    
    # Generate reports
    Write-Host "[*] Generating reports..." -ForegroundColor Cyan
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $baseName = "WebAnalysis_$timestamp"
    
    if ($OutputFormat -eq "text" -or $OutputFormat -eq "both") {
        Export-TextReport -OutputFile "$OutputFolder\$baseName.txt"
    }
    
    if ($OutputFormat -eq "html" -or $OutputFormat -eq "both") {
        Export-HTMLReport -OutputFile "$OutputFolder\$baseName.html"
    }
    
    if ($OutputFormat -eq "mermaid") {
        Export-MermaidDiagram -OutputFile "$OutputFolder\$baseName.mmd"
    }
    
    if ($OutputFormat -eq "json") {
        Export-JSONReport -OutputFile "$OutputFolder\$baseName.json"
    }
    
    if ($OutputFormat -eq "graphviz") {
        Export-GraphvizDiagram -OutputFile "$OutputFolder\$baseName.dot"
    }
    
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "  ANALYSIS SUMMARY" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Total Resources     : " -NoNewline -ForegroundColor Yellow
    Write-Host $global:stats.TotalRequests
    
    Write-Host "Successful Requests : " -NoNewline -ForegroundColor Yellow
    Write-Host $global:stats.SuccessfulRequests -ForegroundColor Green
    
    Write-Host "Failed Requests     : " -NoNewline -ForegroundColor Yellow
    Write-Host $global:stats.FailedRequests -ForegroundColor Red
    
    Write-Host "Total Size          : " -NoNewline -ForegroundColor Yellow
    Write-Host (Format-FileSize $global:stats.TotalSize) -ForegroundColor Cyan
    
    Write-Host "Unique Domains      : " -NoNewline -ForegroundColor Yellow
    Write-Host $global:stats.UniqueDomains.Count -ForegroundColor Cyan
    
    Write-Host ""
    Write-Host "Resources by Type:" -ForegroundColor Yellow
    foreach ($type in $global:urlsByType.Keys | Sort-Object) {
        $count = $global:urlsByType[$type].Count
        if ($count -gt 0) {
            Write-Host "  - $type" -NoNewline -ForegroundColor White
            Write-Host " : $count" -ForegroundColor Cyan
        }
    }
    
    Write-Host ""
    Write-Host "Reports Location    : " -NoNewline -ForegroundColor Yellow
    Write-Host $OutputFolder -ForegroundColor Green
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    
    # Open HTML report if generated
    if ($OutputFormat -eq "html" -or $OutputFormat -eq "both") {
        $htmlFile = "$OutputFolder\$baseName.html"
        Write-Host ""
        $openReport = Read-Host "Open HTML report in browser? (Y/N)"
        if ($openReport -eq "Y" -or $openReport -eq "y") {
            Start-Process $htmlFile
        }
    }
    
} catch {
    Write-Host ""
    Write-Host "[!] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

## --
## Function to generate GraphViz diagram
## --
function Export-GraphvizDiagram {
    param([string]$OutputFile)
    
    $dot = "digraph WebDependencies {`n"
    $dot += "    rankdir=TB;`n"
    $dot += "    node [shape=box, style=filled, fontname=`"Arial`"];`n"
    $dot += "    edge [color=`"#999999`"];`n`n"
    
    # Define colors for different types
    $typeColors = @{
        "HTML" = "#667eea"
        "CSS" = "#264de4"
        "JavaScript" = "#f0db4f"
        "Image" = "#7ed956"
        "Font" = "#e67e22"
        "Media" = "#9b59b6"
        "AJAX" = "#3498db"
        "Other" = "#95a5a6"
    }
    
    $nodeId = 0
    $nodeMap = @{}
    
    # Create nodes
    foreach ($url in $global:discoveredURLs.Keys) {
        $nodeId++
        $nodeName = "node$nodeId"
        $nodeMap[$url] = $nodeName
        
        $info = $global:discoveredURLs[$url]
        $type = $info.Type
        $status = $info.Status
        
        # Create label
        $uri = [System.Uri]$url
        $label = $uri.Host + $uri.PathAndQuery
        if ($label.Length -gt 50) {
            $label = $label.Substring(0, 47) + "..."
        }
        $label = $label -replace '"', '\"'
        
        # Determine color
        $color = if ($status -eq "Failed") { "#dc3545" } 
                 elseif ($typeColors.ContainsKey($type)) { $typeColors[$type] }
                 else { "#95a5a6" }
        
        $fontColor = if ($type -eq "JavaScript") { "black" } else { "white" }
        
        $dot += "    $nodeName [label=`"$label`", fillcolor=`"$color`", fontcolor=`"$fontColor`"];`n"
    }
    
    $dot += "`n"
    
    # Create edges
    foreach ($url in $global:discoveredURLs.Keys) {
        $deps = $global:discoveredURLs[$url].Dependencies
        if ($deps.Count -gt 0) {
            $fromNode = $nodeMap[$url]
            foreach ($dep in $deps) {
                $depURL = $dep.URL
                if ($nodeMap.ContainsKey($depURL)) {
                    $toNode = $nodeMap[$depURL]
                    $dot += "    $fromNode -> $toNode;`n"
                }
            }
        }
    }
    
    $dot += "}`n"
    
    $dot | Out-File -FilePath $OutputFile -Encoding UTF8
    Write-Host "[+] GraphViz diagram saved: $OutputFile" -ForegroundColor Green
    Write-Host "    Generate image with: dot -Tpng $OutputFile -o output.png" -ForegroundColor Yellow
}

## --
## End of script
##
