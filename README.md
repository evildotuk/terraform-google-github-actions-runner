# Terraform Google GitHub Actions Runner

Creates two service accounts and a persistent organization- or repository-level GitHub Actions runner:

- **Packer builder account** builds immutable runner images.
- **Runner runtime account** runs GitHub Actions jobs.

All Terraform resources live in repository root. Packer files live under [`packer/`](packer/).

## Example: external organization

Example projects:

- Images: `acme-runner-images`
- Runners: `acme-ci-runners`
- Secrets: `acme-security`
- GitHub organization: `acme`

```hcl
data "google_project" "runner" {
  project_id = "acme-ci-runners"
}

module "runner" {
  source = "git::https://github.com/evildotuk/terraform-google-github-actions-runner?ref=PIN_A_TAG_OR_COMMIT"

  gcp_project = "acme-ci-runners"
  gcp_zone    = "europe-west2-a"

  runner_scope = "repository"
  ci_owner     = "acme"
  ci_repo      = "payments-api"
  runner_labels = ["gcp", "docker", "pci"]

  ci_token_secret_project = "acme-security"
  ci_token_secret_id      = "github-runner-admin-token"

  boot_image = "projects/acme-runner-images/global/images/family/github-actions-runner"

  network_interface  = "projects/acme-ci-runners/global/networks/ci"
  network_subnetwork = "projects/acme-ci-runners/regions/europe-west2/subnetworks/runners"
  assign_public_ip   = false

  packer_project_id      = "acme-runner-images"
  packer_executor_member = "user:platform-admin@acme.example"
  packer_image_user_members = [
    "serviceAccount:${data.google_project.runner.number}@cloudservices.gserviceaccount.com",
  ]
}
```

Secret must contain GitHub API credential allowed to create runner registration and removal tokens. It is not itself a registration token.

Permissions depend on scope:

- `repository`: repository **Administration: write**
- `organization`: organization **Self-hosted runners: write**

For organization scope, use:

```hcl
runner_scope = "organization"
ci_owner     = "acme"
ci_repo      = null
```

## Create GitHub credential secret

Create secret payload outside Terraform so credential never enters Terraform state:

```bash
export GITHUB_RUNNER_ADMIN_TOKEN='REPLACE_ME'

gcloud secrets create github-runner-admin-token \
  --project=acme-security \
  --replication-policy=automatic

printf '%s' "$GITHUB_RUNNER_ADMIN_TOKEN" | \
  gcloud secrets versions add github-runner-admin-token \
    --project=acme-security \
    --data-file=-

unset GITHUB_RUNNER_ADMIN_TOKEN
```

Module enables Secret Manager API and grants runner service account `roles/secretmanager.secretAccessor` on this secret only. Terraform executor needs permission to enable API and change secret IAM policy in secret project.

## First deployment

Image must exist before runner VM can be created, so first deployment has three steps.

### 1. Create Packer identity and IAM

Use targeted apply only for initial bootstrap:

```bash
terraform apply \
  -target=module.runner.google_project_iam_member.packer_executor_compute \
  -target=module.runner.google_service_account_iam_member.packer_executor_act_as \
  -target=module.runner.google_project_iam_member.packer_image_users
```

Dependencies also create required APIs and Packer builder service account.

### 2. Build image

```bash
cp packer/example.pkrvars.hcl.example packer/local.pkrvars.hcl
```

Set image project, zone, runner version, and published checksum. Default Packer service account ID matches Terraform automatically:

```hcl
project_id     = "acme-runner-images"
zone           = "europe-west2-a"
runner_version = "REPLACE_WITH_RUNNER_VERSION"
runner_sha256  = "REPLACE_WITH_PUBLISHED_LINUX_X64_SHA256"
trivy_version  = "REPLACE_WITH_TRIVY_VERSION"
trivy_sha256   = "REPLACE_WITH_PUBLISHED_LINUX_64BIT_SHA256"
```

Build:

```bash
packer init packer/github-runner.pkr.hcl
packer build -var-file=packer/local.pkrvars.hcl packer/github-runner.pkr.hcl
```

See [`packer/README.md`](packer/README.md) for image details.

### 3. Apply everything

```bash
terraform apply
```

Do not use targeted applies for routine changes.

## Runner labels

Add optional custom labels with `runner_labels`. GitHub default labels (`self-hosted`, OS, and architecture) remain enabled.

```hcl
runner_labels = ["gcp", "docker", "pci"]
```

Target them in workflow:

```yaml
jobs:
  build:
    runs-on: [self-hosted, gcp, pci]
```

Labels route jobs but are not a security boundary. Use repository scope or restricted organization runner groups for access control.

## Artifact Registry access

Grant access in repository-owning project, using runtime account output:

```hcl
resource "google_artifact_registry_repository_iam_member" "runner_writer" {
  project    = "acme-artifacts"
  location   = "europe-west2"
  repository = "containers"
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${module.runner.runner_service_account_email}"
}
```

Use `roles/artifactregistry.reader` for pull-only workflows.

## Existing image only

To skip Packer resource creation, leave `packer_executor_member` unset and pass an existing `boot_image`.

## Current limitations

- Repository scope is preferred for sensitive workloads because only one repository can schedule jobs on that runner.
- Runner is persistent and keeps Docker/build caches between jobs.
- Docker group membership is effectively root-equivalent.
- Secret Manager removes GitHub credential from Terraform state and VM metadata, but trusted jobs with host control can still use VM identity to read secret. External token broker remains stronger isolation.
- Public IP is disabled by default. Private subnet must provide controlled outbound access through Cloud NAT or another egress path.
