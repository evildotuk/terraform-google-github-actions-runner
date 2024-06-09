# README

Sample Terraform Code

```terraform
resource "google_compute_network" "vpc" {
  name                    = "vpc"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "vm-subnet" {
  name                     = "github-build"
  ip_cidr_range            = "192.168.222.0/24"
  network                  = google_compute_network.vpc.name
  depends_on               = [google_compute_network.vpc]
  region                   = var.region
  private_ip_google_access = true
}

module "ci" {
  source = "git::https://github.com/evildotuk/terraform-google-github-actions-runner"

  gcp_project = var.gcp_project
  gcp_zone    = var.gcp_zone
  ci_token = var.ci_token
  ci_repo  = var.ci_repo
  ci_owner = var.ci_owner
  boot_disk_type = "pd-ssd"
  ci_runner_disk_size = 200
  ci_runner_instance_type = "n2-custom-8-8192"
  network_interface  = google_compute_network.vpc.name
  network_subnetwork = google_compute_subnetwork.vm-subnet.name
  depends_on = [
    google_compute_network.vpc,
    google_compute_subnetwork.vm-subnet
  ]
}

resource "google_compute_firewall" "docker-ssh" {
  name    = "docker-internal-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [google_compute_subnetwork.vm-subnet.ip_cidr_range, "35.235.240.0/20"] # our subnet + google IAP (https://cloud.google.com/iap/docs/using-tcp-forwarding)
}
```
<!-- BEGIN_TF_DOCS -->
Copyright 2022-2024 EDOT Ltd
Copyright 2021 Mantel Group Pty Ltd

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.14 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [google_compute_instance_group_manager.ci-runner-gm](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_group_manager) | resource |
| [google_compute_instance_template.ci_runner](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance_template) | resource |
| [google_project_iam_binding.monitoring-writer-role](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/project_iam_binding) | resource |
| [google_service_account.ci_runner](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/service_account) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_boot_disk_type"></a> [boot\_disk\_type](#input\_boot\_disk\_type) | n/a | `string` | `"pd-balanced"` | no |
| <a name="input_boot_image"></a> [boot\_image](#input\_boot\_image) | n/a | `string` | `"ubuntu-2404-lts"` | no |
| <a name="input_ci_owner"></a> [ci\_owner](#input\_ci\_owner) | The repository organisation name / username from GitHub. | `string` | n/a | yes |
| <a name="input_ci_repo"></a> [ci\_repo](#input\_ci\_repo) | The runner repository from GitHub. | `string` | n/a | yes |
| <a name="input_ci_runner_disk_size"></a> [ci\_runner\_disk\_size](#input\_ci\_runner\_disk\_size) | The size of the persistent disk in GB. | `string` | `"20"` | no |
| <a name="input_ci_runner_instance_type"></a> [ci\_runner\_instance\_type](#input\_ci\_runner\_instance\_type) | The instance type used for the runner. This shouldn't need to be changed because the builds<br>themselves run on separate worker instances. | `string` | `"n2-standard-4"` | no |
| <a name="input_ci_token"></a> [ci\_token](#input\_ci\_token) | The runner registration token obtained from GitHub. | `string` | n/a | yes |
| <a name="input_gcp_project"></a> [gcp\_project](#input\_gcp\_project) | The GCP project to deploy the runner into. | `string` | n/a | yes |
| <a name="input_gcp_resource_prefix"></a> [gcp\_resource\_prefix](#input\_gcp\_resource\_prefix) | The prefix to apply to all GCP resource names (e.g. <prefix>-runner, <prefix>-worker-1). | `string` | `"github-ci"` | no |
| <a name="input_gcp_zone"></a> [gcp\_zone](#input\_gcp\_zone) | The GCP zone to deploy the runner into. | `string` | n/a | yes |
| <a name="input_network_interface"></a> [network\_interface](#input\_network\_interface) | (Required) Networks to attach to the instance. This can be specified multiple times. Structure is documented below. | `string` | `"default"` | no |
| <a name="input_network_subnetwork"></a> [network\_subnetwork](#input\_network\_subnetwork) | (Optional) The name or self\_link of the subnetwork to attach this interface to. The subnetwork must exist in the same region this instance will be created in. If network isn't provided it will be inferred from the subnetwork. | `string` | `null` | no |
| <a name="input_preemptible"></a> [preemptible](#input\_preemptible) | n/a | `bool` | `true` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->