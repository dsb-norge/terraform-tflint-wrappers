# terraform-tflint-wrappers

Repo for DSBs TFLint wrapper scripts, ref. https://github.com/terraform-linters/tflint

The intention of tge scripts in this repo is to provide a comaptible and safe way of installing and running TFLint without having to duplicate code in DSBs terraform project repos.


## Bash

### Call wrapper from remote repo
This is how to call the linux wrapper script from bash without storing a copy locally:
```bash
# Without arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh \
| bash -s --

# With arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh \
| bash -s -- --uninstall
```

## Powershell

### Call wrapper from remote repo
This is how to call the powershell wrapper script without storing a copy locally:
```powershell
# Without arguments
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_windows.ps1'))

# With arguments
Invoke-Command `
  -ScriptBlock ([scriptblock]::Create(((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_windows.ps1')) -join "`n")) `
  -ArgumentList $false,$true # Force = false, Remove = true
```

### Development
To simulate calling the script from a remote repo during development use:
```powershell
# Without arguments
Invoke-Expression ([String]::Join("`n",(Get-Content '.\tflint_windows.ps1')))

# With arguments
Invoke-Command `
  -ScriptBlock ([scriptblock]::Create((Get-Content '.\tflint_windows.ps1') -join "`n")) `
  -ArgumentList $false,$true # Force = false, Remove = true
```