/**
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

# Compute the runner name to use for registration in GitHub.  We provide a default based on the GCP project name but it
# can be overridden if desired.
locals {
  ci_runner_github_name_final = (var.ci_runner_github_name != "" ? var.ci_runner_github_name : "gcp-${var.gcp_project}")
}

# Service account for the GitHub CI runner.  It doesn't run builds but it spawns other instances that do.
resource "google_service_account" "ci_runner" {
  project      = var.gcp_project
  account_id   = "${var.gcp_resource_prefix}-runner"
  display_name = "GitHub CI Runner"
}

resource "google_compute_instance" "ci_runner" {
  project      = var.gcp_project
  name         = "${var.gcp_resource_prefix}-runner"
  machine_type = var.ci_runner_instance_type
  zone         = var.gcp_zone

  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "ubuntu-1804-lts"
      size  = var.ci_runner_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    network    = var.network_interface
    subnetwork = var.network_subnetwork
    access_config {
      // Ephemeral IP
    }
  }
  metadata = {
    "shutdown-script" =<<SCRIPT
    #stop and uninstall the runner service
    cd /runner || exit
    ./svc.sh stop
    ./svc.sh uninstall
    #remove the runner configuration
    token=$(curl -s -XPOST \
    -H "authorization: token ${var.ci_token}" \
    https://api.github.com/repos/${var.ci_owner}/${var.ci_repo}/actions/runners/registration-token | jq -r .token)
    RUNNER_ALLOW_RUNASROOT=1  /runner/config.sh remove --unattended --token $token
  SCRIPT
  }

  metadata_startup_script = <<SCRIPT
    set -e
    apt-get update
    apt-get -y install jq docker.io docker-containerd git
    #github runner version
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" 
    chmod a+x /usr/local/bin/kubectl
    # GH_RUNNER_VERSION="2.278.0"
    #get actions binary
    curl -o actions.tar.gz --location "https://github.com/actions/runner/releases/download/v2.278.0/actions-runner-linux-x64-2.278.0.tar.gz"
    mkdir /runner
    mkdir /runner-tmp
    tar -zxf actions.tar.gz --directory /runner
    rm -f actions.tar.gz
    /runner/bin/installdependencies.sh
    #get actions token
    # shellcheck disable=SC2034
    # ACTIONS_RUNNER_INPUT_NAME is used by config.sh
    token=$(curl -s -XPOST \
    -H "authorization: token ${var.ci_token}" \
    https://api.github.com/repos/${var.ci_owner}/${var.ci_repo}/actions/runners/registration-token | jq -r .token)
    ACTIONS_RUNNER_INPUT_NAME=$HOSTNAME
    #configure runner
    RUNNER_ALLOW_RUNASROOT=1 /runner/config.sh --unattended --replace --work "/runner-tmp" --url https://github.com/${var.ci_owner}/${var.ci_repo} --token $token
    #install and start runner service
    cd /runner || exit
    ./svc.sh install
    ./svc.sh start
SCRIPT

  service_account {
    email  = google_service_account.ci_runner.email
    scopes = ["cloud-platform", "logging-write", "monitoring"] # TODO: not really?
  }
}

