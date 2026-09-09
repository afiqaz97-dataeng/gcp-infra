variable "dataset_id" {
  type = string
}

variable "project_id" {
  type = string
}

variable "location" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

resource "google_bigquery_dataset" "this" {
  dataset_id  = var.dataset_id
  project     = var.project_id
  location    = var.location
  description = var.description

  # Terraform's lifecycle block only accepts literal values, not variables,
  # so this is hardcoded rather than exposed as an input. Every dataset here
  # holds real pipeline output — a plan that tries to destroy/recreate one
  # should fail loudly instead of auto-applying on merge.
  lifecycle {
    prevent_destroy = true
  }
}

output "dataset_id" {
  value = google_bigquery_dataset.this.dataset_id
}
