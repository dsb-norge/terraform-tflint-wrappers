# terraform-tflint-wrappers

Repo for DSBs TFLint wrapper scripts, ref. https://github.com/terraform-linters/tflint

The intention of the scripts in this repo is to provide a comaptible and safe way of installing and running TFLint without having to duplicate code in DSBs terraform project repos.


## Call wrapper from remote repo

### Bash
This is how to call the linux wrapper script from bash without having to store a copy locally:
```bash
# Without arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh |
  bash -s --

# With arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh |
  bash -s -- --uninstall
```

### Powershell
This is how to call the powershell wrapper script without having to store a copy locally:
```powershell
# Without arguments
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_windows.ps1'))

# With arguments
Invoke-Command `
  -ScriptBlock ([scriptblock]::Create(((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_windows.ps1')) -join "`n")) `
  -ArgumentList $false,$true,$false # Force = false, Remove = true, ExitWithCode = false
```

## Development

### Bash
To simulate calling the script from a remote repo during development use:
```bash
# Without arguments
bash -s -- < tflint_linux.sh

# With arguments
bash -s -- --uninstall < tflint_linux.sh
```

## Powershell
To simulate calling the script from a remote repo during development use:
```powershell
# Without arguments
Invoke-Expression ([String]::Join("`n",(Get-Content '.\tflint_windows.ps1')))

# With arguments
Invoke-Command `
  -ScriptBlock ([scriptblock]::Create((Get-Content '.\tflint_windows.ps1') -join "`n")) `
  -ArgumentList $true,$false,$false # Force = true, Remove = true, ExitWithCode = false
```