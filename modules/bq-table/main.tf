variable "project_id" {
  type = string
}

variable "dataset_id" {
  type = string
}

variable "table_id" {
  type = string
}

variable "schema" {
  description = "JSON schema string, e.g. file(\"schema.json\"). Required for native tables, ignored for external tables (autodetect)."
  type        = string
  default     = null
}

variable "external_data_configuration" {
  description = "Set to make this an external table over GCS data instead of a native table."
  type = object({
    source_uris   = list(string)
    source_format = string # e.g. "PARQUET", "NEWLINE_DELIMITED_JSON"
    autodetect    = optional(bool, true)
  })
  default = null
}

resource "google_bigquery_table" "this" {
  project    = var.project_id
  dataset_id = var.dataset_id
  table_id   = var.table_id
  schema     = var.external_data_configuration == null ? var.schema : null

  dynamic "external_data_configuration" {
    for_each = var.external_data_configuration == null ? [] : [var.external_data_configuration]
    content {
      source_uris   = external_data_configuration.value.source_uris
      source_format = external_data_configuration.value.source_format
      autodetect    = external_data_configuration.value.autodetect
    }
  }

  # Real pipeline output lives here — see modules/bq-dataset for why this is
  # a hardcoded literal rather than a variable.
  lifecycle {
    prevent_destroy = true
  }
}

output "table_id" {
  value = google_bigquery_table.this.table_id
}
