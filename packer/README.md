# Packer runner image

Builds an Ubuntu 24.04 LTS amd64 image containing:

- Docker Engine, Buildx, and Compose
- Google Cloud CLI, GKE auth plugin, and kubectl
- Google Cloud Ops Agent
- Pinned GitHub Actions runner
- Pinned Trivy CLI
- Non-root `actions-runner` user with a persistent Trivy cache

## Prerequisites

Root Terraform configuration creates Packer builder service account and IAM when `packer_executor_member` is set. Complete initial targeted apply from root [`README.md`](../README.md) before building.

Packer executor needs network access to temporary builder VM. Shared VPC or internal-only builds may require additional host-project networking permissions.

## Configure

```bash
cp packer/example.pkrvars.hcl.example packer/local.pkrvars.hcl
```

Required values:

- `project_id`: image project
- `zone`: temporary builder VM zone
- `service_account_id`: optional override; must match root Terraform `packer_service_account_id`
- `runner_version`: pinned version without leading `v`
- `runner_sha256`: published Linux x64 archive checksum
- `trivy_version`: pinned version without leading `v`
- `trivy_sha256`: published Linux 64-bit archive checksum

## Validate and build

```bash
packer init packer/github-runner.pkr.hcl
packer fmt -check packer/github-runner.pkr.hcl
packer validate -var-file=packer/local.pkrvars.hcl packer/github-runner.pkr.hcl
packer build -var-file=packer/local.pkrvars.hcl packer/github-runner.pkr.hcl
```

Successful builds join `github-actions-runner` image family by default. Ignored build metadata is written to `packer/packer-manifest.json`.

## Terraform image reference

Immutable image, recommended for controlled rollout:

```hcl
boot_image = "projects/IMAGE_PROJECT/global/images/github-actions-runner-20260830120000"
```

Latest successful family image:

```hcl
boot_image = "projects/IMAGE_PROJECT/global/images/family/github-actions-runner"
```

## Trivy

Trivy is installed as root-owned mode `0755` at `/usr/local/bin/trivy`, so non-root jobs can execute it. Vulnerability databases are not baked into the image; scans update and reuse `/home/actions-runner/.cache/trivy` at runtime.

## Updates

Runner registration uses `--disableupdate`. Rebuild image within 30 days of each GitHub runner release and whenever Ubuntu, Docker, Google Cloud CLI, kubectl, Trivy, or Ops Agent changes. Keep previous known-good image for rollback.
