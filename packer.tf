locals {
  packer_enabled    = var.packer_executor_member != null
  packer_project_id = coalesce(var.packer_project_id, var.gcp_project)
}

resource "google_project_service" "packer_compute" {
  count = local.packer_enabled ? 1 : 0

  project            = local.packer_project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "packer_iam" {
  count = local.packer_enabled ? 1 : 0

  project            = local.packer_project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "packer_builder" {
  count = local.packer_enabled ? 1 : 0

  project      = local.packer_project_id
  account_id   = var.packer_service_account_id
  display_name = "GitHub runner Packer builder"

  depends_on = [google_project_service.packer_iam]
}

resource "google_project_iam_member" "packer_executor_compute" {
  count = local.packer_enabled ? 1 : 0

  project = local.packer_project_id
  role    = "roles/compute.instanceAdmin.v1"
  member  = var.packer_executor_member

  depends_on = [google_project_service.packer_compute]
}

resource "google_service_account_iam_member" "packer_executor_act_as" {
  count = local.packer_enabled ? 1 : 0

  service_account_id = google_service_account.packer_builder[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = var.packer_executor_member
}

resource "google_project_iam_member" "packer_image_users" {
  for_each = local.packer_enabled ? var.packer_image_user_members : toset([])

  project = local.packer_project_id
  role    = "roles/compute.imageUser"
  member  = each.value
}
