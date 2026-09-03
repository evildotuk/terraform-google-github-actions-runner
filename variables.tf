/**
 * Copyright 2022-2024 EDOT Ltd
 * Copyright 2021 Mantel Group Pty Ltd
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

# Global options
variable "ci_token_secret_id" {
  type        = string
  description = "Existing Secret Manager secret ID containing the GitHub API credential. Secret payload must be created outside Terraform."
}

variable "ci_token_secret_project" {
  type        = string
  default     = null
  description = "Project containing ci_token_secret_id. Defaults to gcp_project."
}

variable "ci_token_secret_version" {
  type        = string
  default     = "latest"
  description = "Secret Manager version read during runner startup and shutdown."
}
variable "runner_scope" {
  type        = string
  default     = "organization"
  description = "GitHub runner scope: organization or repository."

  validation {
    condition     = contains(["organization", "repository"], var.runner_scope)
    error_message = "runner_scope must be organization or repository."
  }
}

variable "runner_labels" {
  type        = list(string)
  default     = []
  description = "Optional custom GitHub runner labels. Default labels such as self-hosted, Linux, and X64 remain enabled."

  validation {
    condition = (
      alltrue([for label in var.runner_labels : can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", label))]) &&
      length(distinct([for label in var.runner_labels : lower(label)])) == length(var.runner_labels)
    )
    error_message = "runner_labels must be unique, non-empty, and contain only letters, digits, dots, underscores, or hyphens."
  }
}

variable "ci_owner" {
  type        = string
  description = "GitHub organization or repository owner."
}

variable "ci_repo" {
  type        = string
  default     = null
  description = "GitHub repository name. Required when runner_scope is repository and ignored for organization scope."
}
variable "gcp_project" {
  type        = string
  description = "The GCP project to deploy the runner into."
}
variable "gcp_zone" {
  type        = string
  description = "The GCP zone to deploy the runner into."
}
variable "gcp_resource_prefix" {
  type        = string
  default     = "github-ci"
  description = "The prefix to apply to all GCP resource names (e.g. <prefix>-runner, <prefix>-worker-1)."
}

# Runner options
variable "ci_runner_disk_size" {
  type        = string
  default     = "30"
  description = "The size of the persistent disk in GB. Must not be smaller than the Packer image disk."
}
variable "ci_runner_instance_type" {
  type        = string
  default     = "n2-standard-4"
  description = <<EOF
The instance type used for the runner. This shouldn't need to be changed because the builds
themselves run on separate worker instances.
EOF
}

variable "network_interface" {
  type        = string
  default     = "default"
  description = "(Required) Networks to attach to the instance. This can be specified multiple times. Structure is documented below."
}

variable "network_subnetwork" {
  type        = string
  default     = null
  description = "(Optional) The name or self_link of the subnetwork to attach this interface to. The subnetwork must exist in the same region this instance will be created in. If network isn't provided it will be inferred from the subnetwork."
}

variable "assign_public_ip" {
  type        = bool
  default     = false
  description = "Assign an external IPv4 address to the runner. Keep false for private runners and provide Cloud NAT or another controlled egress path."
}

variable "boot_disk_type" {
  type    = string
  default = "pd-balanced"
}

variable "boot_image" {
  type        = string
  description = "Packer-built runner image self-link or family reference. See packer/README.md."
}

variable "preemptible" {
  type    = bool
  default = true
}

# Packer image builder options
variable "packer_project_id" {
  type        = string
  default     = null
  description = "Project used to build and store runner images. Defaults to gcp_project."
}

variable "packer_service_account_id" {
  type        = string
  default     = "github-runner-packer"
  description = "Account ID for the service account attached to temporary Packer builder VMs."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.packer_service_account_id))
    error_message = "Service account ID must contain 6-30 lowercase letters, digits, or hyphens, start with a letter, and end with a letter or digit."
  }
}

variable "packer_executor_member" {
  type        = string
  default     = null
  description = "IAM member running Packer. When null, this module does not create Packer builder resources."
}

variable "packer_image_user_members" {
  type        = set(string)
  default     = []
  description = "IAM members allowed to consume images from packer_project_id. For a cross-project MIG, include the runner project's Google APIs Service Agent."
}
