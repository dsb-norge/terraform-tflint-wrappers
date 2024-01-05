# Configuring TFLint
#   https://github.com/terraform-linters/tflint/blob/master/docs/user-guide/config.md
config {
  call_module_type = "local"
}

# TFLint Ruleset for terraform-provider-azurerm
#   https://github.com/terraform-linters/tflint-ruleset-azurerm
plugin "azurerm" {
  enabled = true
  version = "0.25.1"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Built-in rules disabled by default
#   https://github.com/terraform-linters/tflint/tree/master/docs/rules
rule "terraform_deprecated_index" { enabled = true }          # Disallow legacy dot index syntax
rule "terraform_unused_declarations" { enabled = true }       # Disallow variables, data sources, and locals that are declared but never used
rule "terraform_comment_syntax" { enabled = true }            # Disallow // comments in favor of #
rule "terraform_documented_outputs" { enabled = true }        # Disallow output declarations without description
rule "terraform_documented_variables" { enabled = true }      # Disallow variable declarations without description
rule "terraform_typed_variables" { enabled = true }           # Disallow variable declarations without type
rule "terraform_naming_convention" { enabled = true }         # Enforces naming conventions for resources, data sources, etc
rule "terraform_required_version" { enabled = false }         # Disallow terraform declarations without require_version
rule "terraform_required_providers" { enabled = false }       # Require that all providers have version constraints through required_providers
rule "terraform_unused_required_providers" { enabled = true } # Check that all required_providers are used in the module
rule "terraform_standard_module_structure" { enabled = true } # Ensure that a module complies with the Terraform Standard Module Structure
