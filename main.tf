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

# Compute the runner name to use for registration in GitHub.  We provide a default based on the GCP project name but it
# can be overridden if desired.
locals {
  ci_runner_github_name_final = (var.ci_runner_github_name != "" ? var.ci_runner_github_name : "gcp-${var.gcp_project}")
}

resource "google_service_account" "ci_runner" {
  project      = var.gcp_project
  account_id   = "${var.gcp_resource_prefix}-runner"
  display_name = "GitHub CI Runner"
}

resource "google_project_iam_binding" "monitoring-writer-role" {
    role    = "roles/monitoring.metricWriter"
    project      = var.gcp_project
     members = [
         "serviceAccount:${google_service_account.ci_runner.email}"
     ]
 }

resource "google_compute_instance_template" "ci_runner" {
  project      = var.gcp_project
  name         = "${var.gcp_resource_prefix}-runner"
  machine_type = var.ci_runner_instance_type

  disk {
      source_image = var.boot_image
      auto_delete  = true
      disk_type    = var.boot_disk_type
      disk_size_gb = var.ci_runner_disk_size
  }

  scheduling {
    preemptible         = var.preemptible
    automatic_restart   = ! var.preemptible
  }

  network_interface {
    network    = var.network_interface
    subnetwork = var.network_subnetwork
    access_config {}
  }
  metadata = {
    "shutdown-script" =<<SCRIPT
    cd /runner || exit
    ./svc.sh stop
    ./svc.sh uninstall
    token=$(curl -s -XPOST -H "authorization: token ${var.ci_token}" \
    https://api.github.com/repos/${var.ci_owner}/${var.ci_repo}/actions/runners/registration-token | jq -r .token)
    RUNNER_ALLOW_RUNASROOT=1  /runner/config.sh remove --unattended --token $token
  SCRIPT
  }

  metadata_startup_script = <<SCRIPT
    set -e
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key --keyring /usr/share/keyrings/docker-archive-keyring.gpg add -
    echo \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add -
    apt-get update
    apt-get -y install jq docker-ce docker-ce-cli containerd.io git google-cloud-sdk-gke-gcloud-auth-plugin
    # GCP agent
    curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh && bash add-monitoring-agent-repo.sh --also-install && service stackdriver-agent start
    curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod a+x /usr/local/bin/kubectl
    export LATEST_GH_RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name[1:]')
    curl -o actions.tar.gz --location "https://github.com/actions/runner/releases/download/v$LATEST_GH_RUNNER_VERSION/actions-runner-linux-x64-$LATEST_GH_RUNNER_VERSION.tar.gz"
    mkdir -p /runner
    mkdir -p /runner-tmp
    tar -zxf actions.tar.gz --directory /runner
    rm -f actions.tar.gz
    /runner/bin/installdependencies.sh
    token=$(curl -s -XPOST -H "authorization: token ${var.ci_token}" \
    https://api.github.com/repos/${var.ci_owner}/${var.ci_repo}/actions/runners/registration-token | jq -r .token)
    export ACTIONS_RUNNER_INPUT_NAME=$HOSTNAME
    ./svc.sh uninstall || true
    RUNNER_ALLOW_RUNASROOT=1 /runner/config.sh remove --token $token || true
    RUNNER_ALLOW_RUNASROOT=1 /runner/config.sh --unattended --replace --work "/runner-tmp" --url https://github.com/${var.ci_owner}/${var.ci_repo} --token $token
    cd /runner || exit
    ./svc.sh install
    ./svc.sh start
    (crontab -l 2>/dev/null; echo "0 * * * * docker system prune -af  --filter \"until=12h\"") | crontab -
    (crontab -l 2>/dev/null; echo "0 * * * * docker builder prune -af  --filter \"until=12h\"") | crontab -
SCRIPT

  service_account {
    email  = google_service_account.ci_runner.email
    scopes = ["cloud-platform", "logging-write", "monitoring", "https://www.googleapis.com/auth/monitoring.write"]
  }
}

resource "google_compute_instance_group_manager" "ci-runner-gm" {
  name               = "${var.gcp_resource_prefix}-runner-gm"
  version {
    instance_template  = google_compute_instance_template.ci_runner.id
  }
  base_instance_name = "${var.gcp_resource_prefix}-runner-gm"
  zone               = var.gcp_zone
  target_size        = "1"
}
