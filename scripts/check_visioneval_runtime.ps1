param()

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
    $current = (Get-Location).Path
    while ($true) {
        if ((Test-Path (Join-Path $current "README.md")) -and
            (Test-Path (Join-Path $current "outputs/generated_models"))) {
            return $current
        }

        $parent = Split-Path -Parent $current
        if ($parent -eq $current -or [string]::IsNullOrWhiteSpace($parent)) {
            throw "Could not find VE_RegionBuilder repo root from $(Get-Location)."
        }
        $current = $parent
    }
}

function Convert-YamlPathValue {
    param([string] $Value)
    $trimmed = $Value.Trim()
    if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
        ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
}

function Get-ConfiguredRscript {
    param([string] $RepoRoot)

    $localRuntime = Join-Path $RepoRoot "configs/local_runtime.yml"
    if (Test-Path $localRuntime) {
        $match = Select-String -Path $localRuntime -Pattern "^\s*rscript\s*:\s*(.+?)\s*$" | Select-Object -First 1
        if ($null -ne $match) {
            $value = Convert-YamlPathValue $match.Matches[0].Groups[1].Value
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return $value
            }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:VE_RSCRIPT)) {
        return $env:VE_RSCRIPT
    }

    return "Rscript"
}

$repoRoot = Get-RepoRoot
$rscript = Get-ConfiguredRscript $repoRoot
$scriptPath = Join-Path $repoRoot "scripts/check_visioneval_runtime.R"

Write-Host "Using Rscript: $rscript"
& $rscript $scriptPath
exit $LASTEXITCODE
