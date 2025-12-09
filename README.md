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

## GitHub Actions Setup

### Required Repository Secrets

To run the GitHub Actions CI/CD workflow, configure the following secrets in your repository (Settings → Secrets and variables → Actions):

**Azure Authentication:**
- `AZURE_CLIENT_ID` - Azure App Registration client ID
- `AZURE_TENANT_ID` - Azure tenant ID
- `AZURE_SUBSCRIPTION_ID` - Azure subscription ID

**Terraform State Backend:**
- `BACKEND_RESOURCE_GROUP` - Resource group containing the state storage account
- `BACKEND_STORAGE_ACCOUNT` - Storage account name for tfstate
- `BACKEND_CONTAINER` - Container name for tfstate
- `BACKEND_KEY` - State file name (e.g., "gkprod.tfstate")

**Terraform Variables (choose one method):**
- `TERRAFORM_TFVARS` - Raw contents of terraform.tfvars, OR
- `TERRAFORM_TFVARS_B64` - Base64-encoded terraform.tfvars

**Azure Key Vault (optional):**
- `KEYVAULT_NAME` - Key Vault name
- `KEYVAULT_TFVARS_SECRET_NAME` - Secret name containing tfvars

### Workflow Details

- Triggers on push to `ENV-*` branches
- Uses GitHub OIDC + Azure App Registration for authentication
- Plan job runs automatically
- Apply job requires approval via GitHub environment `production`
- Runs Checkov for security scanning

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
