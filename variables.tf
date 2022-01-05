/**
 * Copyright 2022 EDOT Ltd
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
variable "ci_token" {
  type        = string
  description = "The runner registration token obtained from GitHub."
}
variable "ci_owner" {
  type        = string
  description = "The repository organisation name / username from GitHub."
}
variable "ci_repo" {
  type        = string
  description = "The runner repository from GitHub."
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
  type    = string
  default = "github-ci"
  description = "The prefix to apply to all GCP resource names (e.g. <prefix>-runner, <prefix>-worker-1)."
}

# Runner options
variable "ci_runner_disk_size" {
  type        = string
  default     = "20"
  description = "The size of the persistent disk in GB."
}
variable "ci_runner_github_name" {
  type        = string
  default     = ""
  description = "Register the runner in GitHub using this name.  If empty the value \"gcp-$${var.gcp_project}\" will be used."
}
variable "ci_runner_github_tags" {
    type        = string
    default     = ""
    description = "Register the runner to execute GitHub jobs with these tags."
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
  type = string
  default = "default"
  description = "(Required) Networks to attach to the instance. This can be specified multiple times. Structure is documented below."
}

variable "network_subnetwork" {
  type = string
  default = null
  description = "(Optional) The name or self_link of the subnetwork to attach this interface to. The subnetwork must exist in the same region this instance will be created in. If network isn't provided it will be inferred from the subnetwork."
}

variable "boot_disk_type" {
  type        = string
  default     = "pd-balanced"
}

variable "boot_image" {
  type = string
  default = "ubuntu-2004-lts"
}

variable "preemptible" {
  type = bool
  default = true
}
