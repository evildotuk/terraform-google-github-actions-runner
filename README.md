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