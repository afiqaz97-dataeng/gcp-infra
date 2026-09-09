# Mirrors flatten-nested-json-dataproc/scripts/{setup_gcp.sh,config.sh.example}.
#
# ⚠️ scripts/config.sh is gitignored in that repo and was never present
# locally, so the two bucket names below are placeholders following that
# script's naming convention, NOT confirmed real values. Confirm against
# your actual config.sh before applying, or this will create new buckets
# instead of adopting existing ones.
#
# NOTE: Dataproc Serverless batches (submit_batch.sh) are one-off job
# submissions, not standing infra, so they're intentionally not managed here.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "crypto-etl-project-465203-tfstate"
    prefix = "flatten-json"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type    = string
  default = "crypto-etl-project-465203"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "data_bucket_name" {
  description = "PLACEHOLDER — confirm against scripts/config.sh's DATA_BUCKET before applying."
  type        = string
  default     = "crypto-etl-project-465203-openfda-data"
}

variable "staging_bucket_name" {
  description = "PLACEHOLDER — confirm against scripts/config.sh's STAGING_BUCKET before applying."
  type        = string
  default     = "crypto-etl-project-465203-dataproc-staging"
}

locals {
  bq_dataset_id = "openfda"
  bq_table_id   = "food_events"
  flattened_path = "flattened/openfda_food_events"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "dataproc.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "data_bucket" {
  source     = "../../modules/gcs-bucket"
  project_id = var.project_id
  name       = var.data_bucket_name
  location   = var.region
}

module "staging_bucket" {
  source     = "../../modules/gcs-bucket"
  project_id = var.project_id
  name       = var.staging_bucket_name
  location   = var.region
}

module "openfda_dataset" {
  source      = "../../modules/bq-dataset"
  project_id  = var.project_id
  dataset_id  = local.bq_dataset_id
  location    = "US"
  description = "Flattened openFDA food adverse event reports (flatten_json.py output)."
}

module "food_events_table" {
  source     = "../../modules/bq-table"
  project_id = var.project_id
  dataset_id = module.openfda_dataset.dataset_id
  table_id   = local.bq_table_id
  external_data_configuration = {
    source_uris   = ["gs://${var.data_bucket_name}/${local.flattened_path}/*.parquet"]
    source_format = "PARQUET"
  }
}
