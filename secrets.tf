locals {
  ci_token_secret_project = coalesce(var.ci_token_secret_project, var.gcp_project)
}

resource "google_project_service" "secret_manager" {
  project            = local.ci_token_secret_project
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_secret_manager_secret_iam_member" "ci_runner_token" {
  project   = local.ci_token_secret_project
  secret_id = var.ci_token_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ci_runner.email}"

  depends_on = [google_project_service.secret_manager]
}
