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


locals {
  ci_repo                  = var.ci_repo == null ? "" : var.ci_repo
  github_runner_api_path   = var.runner_scope == "repository" ? "repos/${var.ci_owner}/${local.ci_repo}" : "orgs/${var.ci_owner}"
  github_runner_url        = var.runner_scope == "repository" ? "https://github.com/${var.ci_owner}/${local.ci_repo}" : "https://github.com/${var.ci_owner}"
  github_runner_labels_arg = length(var.runner_labels) > 0 ? "--labels \"${join(",", var.runner_labels)}\"" : ""
}

resource "google_service_account" "ci_runner" {
  project      = var.gcp_project
  account_id   = "${var.gcp_resource_prefix}-runner"
  display_name = "GitHub CI Runner"
}

resource "google_project_iam_member" "monitoring-writer-role" {
  role    = "roles/monitoring.metricWriter"
  project = var.gcp_project
  member  = "serviceAccount:${google_service_account.ci_runner.email}"
}

resource "google_project_iam_member" "logging-writer-role" {
  role    = "roles/logging.logWriter"
  project = var.gcp_project
  member  = "serviceAccount:${google_service_account.ci_runner.email}"
}

resource "google_compute_instance_template" "ci_runner" {
  project      = var.gcp_project
  name_prefix  = "${var.gcp_resource_prefix}-runner-"
  machine_type = var.ci_runner_instance_type

  disk {
    source_image = var.boot_image
    auto_delete  = true
    disk_type    = var.boot_disk_type
    disk_size_gb = var.ci_runner_disk_size
  }

  scheduling {
    preemptible       = var.preemptible
    automatic_restart = !var.preemptible
  }

  network_interface {
    network    = var.network_interface
    subnetwork = var.network_subnetwork

    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }
  metadata = {
    "shutdown-script" = <<SCRIPT
    set -Eeuo pipefail
    cd /runner || exit
    ./svc.sh stop || true
    ./svc.sh uninstall || true
    github_api_token=$(gcloud secrets versions access "${var.ci_token_secret_version}" \
      --project="${local.ci_token_secret_project}" \
      --secret="${var.ci_token_secret_id}")
    token=$(curl --fail-with-body --silent --show-error --location --retry 3 \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $github_api_token" \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "https://api.github.com/${local.github_runner_api_path}/actions/runners/remove-token" | jq -er .token)
    unset github_api_token
    runuser -u actions-runner -- env HOME=/home/actions-runner \
      /runner/config.sh remove --unattended --token "$token"
  SCRIPT
  }

  metadata_startup_script = <<SCRIPT
    set -Eeuo pipefail
    test -x /runner/config.sh
    github_api_token=$(gcloud secrets versions access "${var.ci_token_secret_version}" \
      --project="${local.ci_token_secret_project}" \
      --secret="${var.ci_token_secret_id}")
    token=$(curl --fail-with-body --silent --show-error --location --retry 5 \
      -X POST \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $github_api_token" \
      -H "X-GitHub-Api-Version: 2026-03-10" \
      "https://api.github.com/${local.github_runner_api_path}/actions/runners/registration-token" | jq -er .token)
    unset github_api_token
    runuser -u actions-runner -- env HOME=/home/actions-runner \
      /runner/config.sh --unattended --replace --disableupdate --name "$HOSTNAME" --work "/runner-tmp" --url "${local.github_runner_url}" --token "$token" ${local.github_runner_labels_arg}
    cd /runner
    ./svc.sh install actions-runner
    ./svc.sh start
    (crontab -l 2>/dev/null; echo "0 * * * * docker system prune -af --filter \"until=12h\"") | crontab -
    (crontab -l 2>/dev/null; echo "0 * * * * docker builder prune -af --filter \"until=12h\"") | crontab -
SCRIPT

  service_account {
    email  = google_service_account.ci_runner.email
    scopes = ["cloud-platform", "logging-write", "monitoring", "https://www.googleapis.com/auth/monitoring.write"]
  }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = var.runner_scope != "repository" || trimspace(local.ci_repo) != ""
      error_message = "ci_repo must be set when runner_scope is repository."
    }
  }

  depends_on = [google_secret_manager_secret_iam_member.ci_runner_token]
}

resource "google_compute_instance_group_manager" "ci-runner-gm" {
  name = "${var.gcp_resource_prefix}-runner-gm"
  version {
    instance_template = google_compute_instance_template.ci_runner.id
  }
  base_instance_name = "${var.gcp_resource_prefix}-runner-gm"
  zone               = var.gcp_zone
  target_size        = "1"
}
