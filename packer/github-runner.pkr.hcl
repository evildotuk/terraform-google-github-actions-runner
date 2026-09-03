packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.1.6, < 2.0.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "GCP project used to build and store the runner image."
}

variable "zone" {
  type        = string
  description = "GCP zone used by the temporary Packer builder VM."
}

variable "service_account_id" {
  type        = string
  default     = "github-runner-packer"
  description = "Account ID created by root Terraform configuration for temporary Packer builder VMs."
}

variable "runner_version" {
  type        = string
  description = "Pinned GitHub Actions runner version, without the leading v."
}

variable "runner_sha256" {
  type        = string
  description = "SHA256 checksum for the pinned Linux x64 runner archive."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{64}$", var.runner_sha256))
    error_message = "Runner SHA256 must be a 64-character hexadecimal checksum."
  }
}

variable "trivy_version" {
  type        = string
  description = "Pinned Trivy version, without the leading v."

  validation {
    condition     = can(regex("^[0-9]+[.][0-9]+[.][0-9]+$", var.trivy_version))
    error_message = "Trivy version must use numeric semantic version format without a leading v."
  }
}

variable "trivy_sha256" {
  type        = string
  description = "SHA256 checksum for the pinned Trivy Linux 64-bit archive."

  validation {
    condition     = can(regex("^[0-9a-fA-F]{64}$", var.trivy_sha256))
    error_message = "Trivy SHA256 must be a 64-character hexadecimal checksum."
  }
}

variable "source_image_family" {
  type        = string
  default     = "ubuntu-2404-lts-amd64"
  description = "Ubuntu 24.04 LTS amd64 image family used as the build source."
}

variable "source_image_project_id" {
  type        = string
  default     = "ubuntu-os-cloud"
  description = "Project containing the source image family."
}

variable "image_family" {
  type        = string
  default     = "github-actions-runner"
  description = "Image family assigned to successful runner image builds."
}

variable "image_name" {
  type        = string
  default     = ""
  description = "Optional image name. A timestamped name is generated when empty."
}

variable "machine_type" {
  type        = string
  default     = "e2-standard-2"
  description = "Machine type used for the temporary Packer builder VM."
}

variable "disk_size" {
  type        = number
  default     = 30
  description = "Boot disk size in GB for the temporary builder VM and resulting image."
}

variable "network" {
  type        = string
  default     = "default"
  description = "Network used by the temporary Packer builder VM."
}

variable "use_internal_ip" {
  type        = bool
  default     = false
  description = "Connect to the builder over its internal IP. Requires private access from the Packer host."
}

locals {
  build_timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
  image_name      = var.image_name != "" ? var.image_name : "github-actions-runner-${local.build_timestamp}"
}

source "googlecompute" "github_runner" {
  project_id              = var.project_id
  zone                    = var.zone
  source_image_family     = var.source_image_family
  source_image_project_id = [var.source_image_project_id]
  image_name              = local.image_name
  image_family            = var.image_family
  image_description       = "GitHub Actions runner ${var.runner_version} on ${var.source_image_family}"
  machine_type            = var.machine_type
  disk_size               = var.disk_size
  network                 = var.network
  use_internal_ip         = var.use_internal_ip
  ssh_username            = "packer"
  service_account_email   = "${var.service_account_id}@${var.project_id}.iam.gserviceaccount.com"
  scopes                  = ["https://www.googleapis.com/auth/cloud-platform"]
}

build {
  name    = "github-actions-runner"
  sources = ["source.googlecompute.github_runner"]

  provisioner "shell" {
    script = "${path.root}/scripts/install-runner.sh"
    environment_vars = [
      "RUNNER_VERSION=${var.runner_version}",
      "RUNNER_SHA256=${lower(var.runner_sha256)}",
      "TRIVY_VERSION=${var.trivy_version}",
      "TRIVY_SHA256=${lower(var.trivy_sha256)}",
    ]
  }

  post-processor "manifest" {
    output = "${path.root}/packer-manifest.json"
    custom_data = {
      image_family   = var.image_family
      image_name     = local.image_name
      runner_version = var.runner_version
      trivy_version  = var.trivy_version
    }
  }
}
