# bundle_project.ps1
# Bundles a Flutter/Dart project (or any code project) into a single .txt file
# so it can be uploaded to Copilot Chat in one shot, then unpacked back into
# individual files preserving folder structure.
#
# USAGE:
#   1. Open PowerShell
#   2. cd into your project root, e.g.:
#        cd C:\projects\PS-EV\ps_ev_flutter
#   3. Run:
#        powershell -ExecutionPolicy Bypass -File bundle_project.ps1
#      (or just paste this script's content directly into a PowerShell window)
#   4. This creates "project_bundle.txt" in the SAME folder.
#   5. Upload only "project_bundle.txt" to the chat.

# ---- CONFIGURATION ----
$ProjectRoot = Get-Location
$OutputFile  = Join-Path $ProjectRoot "project_bundle.txt"

# File extensions to include (add more if needed)
$IncludeExtensions = @(
    "*.dart", "*.yaml", "*.yml", "*.json", "*.gradle",
    "*.xml", "*.md", "*.txt", "*.plist", "*.kt", "*.swift"
)

# Folders to skip (build artifacts, dependencies, IDE junk, version control)
$ExcludeDirs = @(
    "build", ".dart_tool", ".idea", ".git", "android\.gradle",
    "ios\Pods", "ios\.symlinks", "node_modules", ".vscode"
)

# ---- SCRIPT LOGIC ----
if (Test-Path $OutputFile) { Remove-Item $OutputFile }

$files = Get-ChildItem -Path $ProjectRoot -Recurse -Include $IncludeExtensions -File |
    Where-Object {
        $relativePath = $_.FullName.Substring($ProjectRoot.Path.Length + 1)
        $skip = $false
        foreach ($dir in $ExcludeDirs) {
            if ($relativePath -like "*$dir*") { $skip = $true; break }
        }
        -not $skip
    }

Write-Host "Found $($files.Count) files to bundle..."

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($ProjectRoot.Path.Length + 1) -replace '\\', '/'
    Add-Content -Path $OutputFile -Value "===== FILE: $relativePath ====="
    Get-Content -Path $file.FullName -Raw | Add-Content -Path $OutputFile
    Add-Content -Path $OutputFile -Value "`n===== END FILE =====`n"
}

Write-Host "Done. Bundle created at: $OutputFile"
Write-Host "File size: $([math]::Round((Get-Item $OutputFile).Length / 1KB, 1)) KB"
