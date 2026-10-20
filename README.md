# terraform-tflint-wrappers

> **Retired.** TFLint is installed and run by the dsb CLI,
> [`dsb-norge/terraform-helpers`](https://github.com/dsb-norge/terraform-helpers): `tf-lint` and
> `tf-lint-all` lint a project's environments and its state directory, and a module repository's
> root and examples, the same way CI does
> ([the lint contract](https://github.com/dsb-norge/github-actions-terraform/blob/main/docs/Linting.md)).
> The CLI also writes the default `.tflint.hcl` into a directory that has none. This repository is
> archived; the scripts below stay readable at their raw URLs but are no longer maintained.

Repo for DSBs TFLint wrapper scripts, ref. <https://github.com/terraform-linters/tflint>

The intention of the scripts in this repo is to provide a compatible and safe way of installing and running TFLint without having to duplicate code in DSBs terraform project repos.

## Call wrapper from remote repo

### Bash from remote repo

This is how to call the linux wrapper script from bash without having to store a copy locally:

```bash
# Without arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh |
  bash -s --

# With arguments
curl -s https://raw.githubusercontent.com/dsb-norge/terraform-tflint-wrappers/main/tflint_linux.sh |
  bash -s -- --help
```

### Powershell from remote repo

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
