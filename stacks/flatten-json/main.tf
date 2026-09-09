# Mirrors flatten-nested-json-dataproc/scripts/{setup_gcp.sh,config.sh.example}.
# Bucket/dataset/table names below were confirmed against the live project
# (gcloud storage buckets list / bq ls), not guessed.
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
  type    = string
  default = "crypto-etl-project-465203-openfda-data"
}

variable "staging_bucket_name" {
  type    = string
  default = "crypto-etl-project-465203-dataproc-staging"
}

locals {
  bq_dataset_id = "openfda"
  bq_table_id   = "food_events_loaded"
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
  source                      = "../../modules/gcs-bucket"
  project_id                  = var.project_id
  name                        = var.data_bucket_name
  location                    = var.region
  uniform_bucket_level_access = false # matches the bucket's existing real setting
}

module "staging_bucket" {
  source                      = "../../modules/gcs-bucket"
  project_id                  = var.project_id
  name                        = var.staging_bucket_name
  location                    = var.region
  uniform_bucket_level_access = false # matches the bucket's existing real setting
}

module "openfda_dataset" {
  source      = "../../modules/bq-dataset"
  project_id  = var.project_id
  dataset_id  = local.bq_dataset_id
  location    = var.region
  description = "Flattened openFDA food adverse event reports (flatten_json.py output)."
}

module "food_events_table" {
  source     = "../../modules/bq-table"
  project_id = var.project_id
  dataset_id = module.openfda_dataset.dataset_id
  table_id   = local.bq_table_id
  schema     = file("${path.module}/schemas/food_events_loaded.json")
}
