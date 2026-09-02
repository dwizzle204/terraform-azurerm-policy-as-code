# Azure Policy Machine Configuration for Virtual Machines

[![cd-machine-config](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/actions/workflows/cd-guest-config.yml/badge.svg)](https://github.com/dwizzle204/terraform-azurerm-policy-as-code/actions/workflows/cd-guest-config.yml)

> 💡 **Note:** Azure Policy Guest Configuration is now called Azure Automanage Machine Configuration. [Learn more about the recent renaming of Microsoft configuration management services.](https://techcommunity.microsoft.com/t5/azure-governance-and-management/coming-soon-guest-configuration-renames-to-machine-configuration/ba-p/3474116)

This folder demonstrates an effective terraform workflow for continuous compliance with [Azure Policy Machine Configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/overview) using PowerShell Desired State Config (DSC).

### Automating CGC Package Deployment

This workflow executes a terraform null resource to run the [build_machine_config_packages.ps1](../scripts/build_machine_config_packages.ps1) PowerShell script which builds and publishes Custom Machine Config (CGC) policy definitions. PS Module dependencies are installed with the `checkDependancies` flag, this list can be updated as required by your custom configs.

On initial run or to rebuild/update existing configs, first target the null resource with parallelism set to 1 before running a complete apply such as below. This will prevent the [`GuestConfiguration`](https://www.powershellgallery.com/packages/GuestConfiguration/) PowerShell module from encountering conflicts during package creation. If the `checkDependancies` flag is unset each config should take approximately 10-15 seconds to publish packages and generate Definitions.

```bash
apply -target null_resource.build_machine_config_packages -parallelism=1 && tf apply
```

Definitions will stored in the local repo library under [Guest Configuration](../policies/Guest%20Configuration/)

### Links

- 📘 [Understand the machine configuration feature of Azure Automanage](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/overview)
- 📘 [Azure Policy guest configuration extension](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/manage/azure-server-management/guest-configuration-policy)
- 📘 [How to set up a machine configuration authoring environment](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/machine-configuration-create-setup)
- 📘 [How to create custom machine configuration package artifacts](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/machine-configuration-create)
- 📘 [How to create custom machine configuration policy definitions](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/machine-configuration-create-definition)
- 📘 [How to test machine configuration package artifacts](https://learn.microsoft.com/en-gb/azure/governance/machine-configuration/machine-configuration-create-test)
- 📘 [Remediation options for machine configuration](https://learn.microsoft.com/en-us/azure/governance/machine-configuration/machine-configuration-policy-effects)
- 📙 [Azure Policy Guest Configuration samples](https://github.com/Azure/azure-policy/tree/master/samples/GuestConfiguration/package-samples)
- 📙 [DSC GitHub Community](https://github.com/dsccommunity)
- 📙 [Terraform Provider: azurerm_policy_virtual_machine_configuration_assignment](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_virtual_machine_configuration_assignment)