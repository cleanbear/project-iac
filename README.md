# Project IAC

Infrastructure as Code for Kalyan Infra's cloud resources on Azure.

## Overview

This repository contains Terraform configurations for deploying and managing Azure infrastructure:

- Virtual Networks (VNets) and Subnets
- Azure Container Registry (ACR)
- Azure Kubernetes Service (AKS)
- Key Vault

## Prerequisites

- Terraform >= 1.0
- Azure CLI
- Azure subscription credentials

## Getting Started

### 1. Clone the Repository

```bash
git clone <repository-url>
cd project-iac
```

### 2. Configure Terraform Variables

Create `terraform.tfvars` with your Azure configuration:

**Important:** Never commit `terraform.tfvars` to version control. It's already in `.gitignore`.

### 3. Run Terraform

```bash
terraform init
terraform plan
terraform apply
```

## Managing Secrets

### GitHub Secrets Method

Store `terraform.tfvars` as a GitHub secret for CI/CD pipelines:

**PowerShell:**
```powershell
$content = Get-Content -Raw -Path 'terraform.tfvars'
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
gh secret set TERRAFORM_TFVARS_B64 --body $b64
```

**Bash:**
```bash
base64 -w0 terraform.tfvars | xargs gh secret set TERRAFORM_TFVARS_B64 --body
```

### Azure Key Vault Method

Store secrets in Key Vault instead:

```bash
az keyvault secret set --vault-name my-kv --name terraform-tfvars --value "$(cat terraform.tfvars)"
```

Set GitHub secrets:
- `KEYVAULT_NAME`: my-kv
- `KEYVAULT_TFVARS_SECRET_NAME`: terraform-tfvars

## File Structure

```
.
 ├── main.tf               # Resource definitions
 ├── provider.tf           # Azure provider configuration
 ├── variable.tf           # Variable definitions
 ├── output.tf             # Outputs
 └── README.md
```

## Security Guidelines

- Never commit `terraform.tfvars` to the repository
- Use GitHub secrets or Key Vault for sensitive values
- Rotate credentials regularly
- Restrict repository access appropriately
- Enable branch protection rules for main branch
