output "runner_service_account_email" {
  description = "Service account email used by GitHub Actions runner VMs."
  value       = google_service_account.ci_runner.email
}

output "runner_service_account_name" {
  description = "Fully qualified service account resource name used by GitHub Actions runner VMs."
  value       = google_service_account.ci_runner.name
}

output "packer_builder_service_account_email" {
  description = "Packer builder service account email, or null when packer_executor_member is unset."
  value       = try(google_service_account.packer_builder[0].email, null)
}

output "packer_builder_service_account_name" {
  description = "Fully qualified Packer builder service account name, or null when packer_executor_member is unset."
  value       = try(google_service_account.packer_builder[0].name, null)
}
