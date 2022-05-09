#
# .SYNOPSIS
# Wrapper script for TFLint - https://github.com/terraform-linters/tflint
#
# .DESCRIPTION
# Perform linting of terraform code using TFLint.
#   - Loops over all *.tfvars (if any)
#   - Loops through all terraform module directories (if any)
#   - Prints summary
#   - Returns the sum of all exit codes for all permutations, 0 when there are no issues
#   - The flag -ExitWithCode can be used to terminate with exit code instead of returning it
#
# If TFLint is missing (or -Force is speciified) the latest version of TFLint will be downloaded and installed to '.\.tflint'.
#
# Prereqs:
#   - terraform init must be performed prior to running this script in order for module directories to be linted
#   - A TFLint configuration file must exists with the name '.tflint.hcl', see https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md
#
# .INPUTS
# None. Pipelining is not supported.
#
# .OUTPUTS
# Outputs:
#   - Detailed results are written to the host.
#   - The sum of all exit codes for all permutations, 0 when there are no issues.
#     If the flag -ExitWithCode is specified, the powershell process will terminate with exit code according to the above and no value will be returned.
#
# .EXAMPLE
#     .\tflint_windows.ps1 -Force
# Force installation of the latest version if TFLint and perform linting in '.\'
#

[CmdletBinding(PositionalBinding = $false)]
param(
    # Support --force-install ex. for upgrading tflint
    [alias('force-install', 'install')]
    [switch]$Force,
    # Support --remove for removing .tflint directory
    [alias('r', 'uninstall')]
    [switch]$Remove,
    # Support flag for exiting current powershell process with exitcode, default is not to exit
    [switch]$ExitWithCode
)

# Need the current working directory
$scriptDir = (Get-Location).Path

# Static variables
$tflintConfigFile = '.tflint.hcl'
$tflintInstallDir = '.tflint'
$tflintLatestReleaseUrl = 'https://github.com/terraform-linters/tflint/releases/latest'
$tflintDefaultConfigUrl = 'https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/default.tflint.hcl'

# Folder and file locations
$tflintInstallDirFullPath = Join-Path -Path $scriptDir -ChildPath $tflintInstallDir
$tflintBinPath = Join-Path -Path $tflintInstallDirFullPath -ChildPath 'tflint.exe'
$tflintConfigFileFullPath = Join-Path -Path $scriptDir -ChildPath $tflintConfigFile
$terraformDir = Join-Path -Path $scriptDir -ChildPath '.terraform'
$terraformModulesJson = Join-Path -Path $terraformDir -ChildPath (Join-Path -Path 'modules' -ChildPath 'modules.json')
$gitignoreFullPath = Join-Path -Path $scriptDir -ChildPath '.gitignore'

# Helper functions
$_tflintDirExists = [scriptblock] { Test-Path -PathType Container -Path $tflintInstallDirFullPath }
$_tflintBinExists = [scriptblock] { Test-Path -PathType Leaf -Path $tflintBinPath }
$_tflintConfigExists = [scriptblock] { Test-Path -PathType Leaf -Path $tflintConfigFileFullPath }
$_terraformDirExists = [scriptblock] { Test-Path -PathType Container -Path $terraformDir }
$_terraformModulesJsonExists = [scriptblock] { Test-Path -PathType Leaf -Path $terraformModulesJson }
$_gitignoreExists = [scriptblock] { Test-Path -PathType Leaf -Path $gitignoreFullPath }

# Print header
$separatorLong = $('=' * 80)
$separatorShort = $('=' * 40)
Write-Host "$separatorLong`n`n`tTFLint - A Pluggable Terraform Linter`n`n$separatorLong"

# Uninstall?
if ( $Remove )
{
    Write-Host "`nUninstalling TFLint ..."
    if ( Invoke-Command $_tflintDirExists )
    {
        Write-Host "Removing dir '$tflintInstallDirFullPath' ..."
        Remove-Item -Force -Recurse -Path $tflintInstallDirFullPath
    }
    Write-Host 'Done.'
    if ( $ExitWithCode )
    {
        Write-Debug "Exiting with code 0"
    exit 0
    }
    else
    {
        Write-Debug "Stoping script execution not calling exit, returning code: 0"
        0
        break
    }
}

# Abort if terraform has not been initialized
if ( -not (Invoke-Command $_terraformDirExists) )
{
    throw "Missing '.terraform' directory. Please perform 'terraform init' first."
}

# Download TFLint if missing or asked to
if ( -not (Invoke-Command $_tflintBinExists) -or $Force )
{
    # Get latest TFLint version
    $latestVersionRequest = [System.Net.WebRequest]::Create($tflintLatestReleaseUrl)
    $latestVersionResponse = $latestVersionRequest.GetResponse()
    $latestVersionTagUrl = $latestVersionResponse.ResponseUri.OriginalString
    $latestTflintVersion = $latestVersionTagUrl.split('/')[-1].Trim('v')

    # Get download url of latest TFLint version
    $downloadFileName = 'tflint_windows_amd64.zip'
    $tflintReleaseDownloadUrl = $latestVersionTagUrl.Replace('tag', 'download') + '/' + $downloadFileName

    # Download TFLint to temp file
    $tempFileName = "$(New-TemporaryFile).zip"
    Write-Host "Downloading version $latestTflintVersion of TFLint ..."
    Write-Host "Source: $tflintReleaseDownloadUrl"
    try
    {
        $ProgressPreference = 'SilentlyContinue'
        $null = Invoke-WebRequest -Uri $tflintReleaseDownloadUrl -OutFile $tempFileName -UseBasicParsing
    }
    catch
    {
        throw ("Failed to save TFLint binary as '$tempFileName' from '$tflintReleaseDownloadUrl'!`nException was:`n{0}" -f $_.Exception)
    }

    # Install TFLint
    Write-Host "Installing TFLint to $tflintInstallDirFullPath ..."
    Expand-Archive -Path $tempFileName -DestinationPath $tflintInstallDirFullPath -Force
    Remove-Item -Path $tempFileName -Force -ErrorAction SilentlyContinue # no longer need the temp file
    if ( -not (Invoke-Command $_tflintBinExists) )
    {
        throw "Unable to find TFLint binary at '$tflintBinPath' after file decompression!"
    }

    # Add install dir to .gitignore when needed
    if ( Invoke-Command $_gitignoreExists )
    {
        Write-Debug ".gitignore already exists, checking for '**/.tflint/*' ..."
        if ( -not (Select-String -Path $gitignoreFullPath -Pattern '\*\*/\.tflint/\*' ) )
        {
            Write-Host "`nUpdate .gitignore: Exclude **/.tflint/* ..."
            Add-Content -Path $gitignoreFullPath -Value "`n# Local tflint directories`n**/.tflint/*"
        }
        else
        {
            Write-Debug ".gitignore already contains **/.tflint/*, skipping update."
        }
    }
}

# Install default TFLint config if config is missing
if ( -not (Invoke-Command $_tflintConfigExists) )
{
    Write-Host "`nMissing TFLint config fetching default config ..."
    Write-Host "Source: $tflintDefaultConfigUrl"
    Write-Host "Target: $tflintConfigFileFullPath"
    try
    {
        $ProgressPreference = 'SilentlyContinue'
        $null = Invoke-WebRequest -Uri $tflintDefaultConfigUrl -OutFile $tflintConfigFileFullPath -UseBasicParsing
    }
    catch
    {
        throw ("Failed to save TFLint default configuration as '$tflintConfigFileFullPath' from '$tflintDefaultConfigUrl'!`nException was:`n{0}" -f $_.Exception)
    }
}

# Abort if config file is still missing
if ( -not (Invoke-Command $_tflintConfigExists) )
{
    throw "Missing TFLint config file at '$tflintConfigFileFullPath'!"
}

Write-Debug "Install TFLint plugins, mute stdout"
& "$tflintBinPath" /init 1>$null

Write-Debug "Look for terraform module directories"
#   Note: modules.json includes the root directory
$directoriesToLint = [string[]]@( '.' )
if ( (Invoke-Command $_terraformModulesJsonExists) )
{
    $directoriesToLint = [string[]]@(
        (Get-Content $terraformModulesJson | ConvertFrom-Json).Modules.Dir `
        | Sort-Object -Unique | ForEach-Object {
            $fullModulePath = Join-Path -Path $scriptDir -ChildPath $_
            # If directory actually exists queue it for linting
            if ( Test-Path -PathType Container -Path $fullModulePath )
            {
                Write-Debug "Directory to be linted: $_"
                $_
            }
        }
    ) | Sort-Object
}

# Look for *.tfvars files
$tfvarsFiles = Get-ChildItem -Path $scriptDir -Filter '*.tfvars' -File | Sort-Object
$lintingResults = @{}
if ( -not $tfvarsFiles )
{
    # $lintingResults will be hashtable with one key
    Write-Debug "No .tfvars files found in $scriptDir"
    $lintingResults += @{ '' = @{} }
}
else
{
    # $lintingResults will be hashtable with each tfvars file as key
    Write-Debug "Found $($tfvarsFiles.count) .tfvars files in $scriptDir"
    $tfvarsFiles | ForEach-Object { $lintingResults += @{ $_.Name = @{} } }
}

# Loop over all directories to lint
foreach ($lintDir in $directoriesToLint)
{
    Write-Host "`nLinting in: $lintDir`n$separatorShort"

    Push-Location $lintDir

    if ( -not $tfvarsFiles ) # no tfvars exists
    {
        # Invoke without '/var-file'
        & "$tflintBinPath" /config:"$tflintConfigFile" . 2>&1
        $lintingResults[''] += @{ $lintDir = $LASTEXITCODE }
    }
    else # tfvars exists, iterate over them
    {
        $tfvarsFiles | ForEach-Object {
            Write-Debug "Linting with tfvars: $($_.Name)"
            # Invoke with '/var-file'
            & "$tflintBinPath" /config:"$tflintConfigFile" /var-file:"$($_.FullName)" .
            $lintingResults[$($_.Name)] += @{ $lintDir = $LASTEXITCODE }
        }
    }

    Pop-Location
}

# Summarize results of linting
Write-Host "`n`nTFLint summary:`n$separatorShort"
foreach ($varFile in ($lintingResults.Keys | Sort-Object) )
{
    foreach ($lintDir in ($lintingResults."$varFile".Keys | Sort-Object) )
    {
        Write-Host $(if ($lintingResults."$varFile"."$lintDir" -ne 0)
            {
                'failure'
            }
            else
            {
                'success'
            }) " -> ./$varFile @ ./$lintDir"
    }
    Write-Host ""
}

# Script will write an error string if any of the invocations failed
$exitcodeSum = ( ($lintingResults[$lintingResults.Keys]).Values | Measure-Object -Sum).Sum
if ( $exitcodeSum -ne 0 )
{
    Write-Error 'FAILURE: Linting with TFLint failed for one or more configurations'
}
if ( $ExitWithCode )
{
    Write-Debug "Exiting with code: $exitcodeSum"
exit $exitcodeSum
}
else
{
    Write-Debug "Not calling exit, returning code: $exitcodeSum"
    $exitcodeSum
}
