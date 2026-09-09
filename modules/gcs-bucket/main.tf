variable "name" {
  type        = string
  description = "Globally unique bucket name."
}

variable "project_id" {
  type = string
}

variable "location" {
  type = string
}

variable "force_destroy" {
  type    = bool
  default = false
}

variable "uniform_bucket_level_access" {
  type    = bool
  default = true
}

variable "lifecycle_rules" {
  description = "Optional list of lifecycle rules, e.g. [{ age_days = 30, action = \"Delete\" }]"
  type = list(object({
    age_days = number
    action   = string
  }))
  default = []
}

resource "google_storage_bucket" "this" {
  name                        = var.name
  project                     = var.project_id
  location                    = var.location
  force_destroy               = var.force_destroy
  uniform_bucket_level_access = var.uniform_bucket_level_access

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules
    content {
      action {
        type = lifecycle_rule.value.action
      }
      condition {
        age = lifecycle_rule.value.age_days
      }
    }
  }
}

output "name" {
  value = google_storage_bucket.this.name
}

output "url" {
  value = google_storage_bucket.this.url
}
