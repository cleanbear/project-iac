# infra-iac

## Managing `terraform.tfvars` using a base64 secret

Your team prefers not to keep an example tfvars file in the repository. The workflow is already configured to support a base64-encoded secret named `TERRAFORM_TFVARS_B64` containing the full `terraform.tfvars` file. This section explains how to create and store that secret securely.

1) Generate a base64-encoded value from your `terraform.tfvars` locally

- PowerShell (Windows):

```powershell
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Path 'terraform.tfvars')))
$b64 | Set-Clipboard   # optional: copy to clipboard
$b64 > tfvars.b64       # optional: save to a file
```

- Linux / macOS:

```bash
base64 -w0 terraform.tfvars > tfvars.b64   # Linux (no wrapping)
# macOS: base64 terraform.tfvars > tfvars.b64
```

2) Create the repository secret in GitHub

- Using GitHub UI: Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
  - Name: `TERRAFORM_TFVARS_B64`
  - Value: paste the base64 string (contents of `tfvars.b64`)

- Using `gh` CLI (PowerShell):

```powershell
gh secret set TERRAFORM_TFVARS_B64 --body (Get-Content tfvars.b64 -Raw)
```

Or (bash):

```bash
gh secret set TERRAFORM_TFVARS_B64 --body "$(cat tfvars.b64)"
```

3) What the workflow does

- The workflow decodes `TERRAFORM_TFVARS_B64` and writes `terraform.tfvars` at runtime before `terraform init` and `plan`.
- The `apply` job runs only after a manual approval if you protect the `production` environment with reviewers.

4) Security notes

- GitHub Secrets are encrypted at rest; Actions masks secrets in logs. Do not add commands that print the secret.
- Limit who can modify workflows and who has admin access to the repo (to avoid secret exfiltration).
- Consider rotating secrets periodically. For stricter security, consider Azure Key Vault + OIDC.

## Using Azure Key Vault instead of repository secrets

If you prefer not to store the tfvars in GitHub at all, you can store the full `terraform.tfvars` as a secret in Azure Key Vault and let the workflow retrieve it at runtime. The workflow supports this mode when two repository secrets are set:

- `KEYVAULT_NAME` : your Key Vault name
- `KEYVAULT_TFVARS_SECRET_NAME` : the name of the secret inside Key Vault that contains the tfvars (value may be raw tfvars or base64-encoded)

Steps to set this up:

1. Create a secret in Key Vault containing either the raw `terraform.tfvars` content or a base64-encoded version of it. Example (Azure CLI):

```bash
az keyvault secret set --vault-name my-kv --name terraform-tfvars --value "$(cat terraform.tfvars)"
# or for base64:
az keyvault secret set --vault-name my-kv --name terraform-tfvars-b64 --value "$(base64 -w0 terraform.tfvars)"
```

2. Ensure your Azure App Registration (the one you configured with the GitHub OIDC federated credential) has permission to read secrets from the Key Vault. Two common ways:

- Key Vault Access Policy (Secret permissions -> Get): add the app registration's service principal and grant `get` on secrets.
- OR use Azure RBAC (Key Vault Secrets User role or custom role) scoped to the vault.

3. Add repository secrets in GitHub:

- `KEYVAULT_NAME` (value: `my-kv`)
- `KEYVAULT_TFVARS_SECRET_NAME` (value: e.g. `terraform-tfvars`)

When the workflow runs it will call `az keyvault secret show` (after `azure/login`) and create `terraform.tfvars` from the secret value. The workflow attempts to base64-decode the retrieved value first; if that fails it writes the raw value.

Security notes for Key Vault approach

- Access is controlled by Azure AD and Key Vault policies — do not grant broader access than necessary.
- The GitHub OIDC + App Registration pattern avoids storing client secrets in GitHub.
- Rotate Key Vault secrets and limit which principal can read them.


If you'd like, I can:
- Enforce using only `TERRAFORM_TFVARS_B64` by removing raw-secret support from the workflow.
- Add per-environment secret names and branch→environment mapping so the workflow picks `TERRAFORM_TFVARS_B64_PROD` for `ENV-prod` branches, etc.
```markdown
# infra-iac
infra-iac

```

## Managing `terraform.tfvars`

Recommendations for handling `terraform.tfvars` securely and reliably:

- **Never commit** real secrets into `terraform.tfvars`. Add `terraform.tfvars` and `*.tfvars` to `.gitignore` (already configured).
- Keep a non-sensitive example in the repo: `terraform.tfvars.example` (already added). Use it as a template.
- For secret values use one of these approaches:
  - **Per-variable GitHub Actions secrets**: store each sensitive var as a repository secret and write `terraform.tfvars` at runtime in the workflow.
  - **Azure Key Vault**: store secrets in Key Vault and retrieve them at workflow runtime after login with OIDC.
  - **Single secret file**: store the entire tfvars file contents in one secret (e.g. `TERRAFORM_TFVARS`) and write to disk during the workflow. Simpler but less flexible.

Example: create `terraform.tfvars` from per-variable secrets in the GitHub Actions workflow:

```yaml
- name: Build terraform.tfvars from secrets
  run: |
    cat > terraform.tfvars <<EOF
    resourceGroupName = "${{ secrets.BACKEND_RESOURCE_GROUP }}"
    location = "${{ secrets.LOCATION }}"
    client_id = "${{ secrets.CLIENT_ID }}"
    client_secret = "${{ secrets.CLIENT_SECRET }}"
    subscription_id = "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
    EOF
```

Example: retrieve secrets from Azure Key Vault after OIDC login:

```yaml
- name: Get secret from Key Vault
  run: |
    secret_value=$(az keyvault secret show --vault-name my-kv --name apiKey --query value -o tsv)
    cat > terraform.tfvars <<EOF
    api_key = "${secret_value}"
    EOF
```

Use the `terraform.tfvars.example` as the baseline and merge secrets at runtime. The repository now contains `terraform.tfvars.example` and `.gitignore` ignores real `terraform.tfvars`.

If you want, I can update the GitHub Actions workflow to automatically build `terraform.tfvars` for each environment (prod/uat/qa/dev) from secrets or Key Vault—tell me which approach you prefer.
# infra-iac
infra-iac
