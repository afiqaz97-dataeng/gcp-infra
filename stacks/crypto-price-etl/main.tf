# Mirrors crypto-price-etl-gcp/{sql,workflow_settings.yaml,cloud_function}.
# NOTE: the Cloud Function itself is intentionally NOT managed here.
# crypto-price-etl-gcp/cloudbuild.yaml already deploys it via
# `gcloud functions deploy` on every push — that stays the deploy path for
# the function's *code*. This stack owns the surrounding data infra: the
# staging bucket the function writes to, and the BigQuery datasets/external
# table that Dataform reads from and writes to.

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
    prefix = "crypto-price-etl"
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
  default = "asia-southeast1"
}

locals {
  staging_bucket_name = "crypto-etl-bucket-af" # hardcoded in cloud_function/main.py
  staging_dataset_id  = "staging_crypto"
  curated_dataset_id  = "curated_crypto" # written by Dataform, see definitions/curated_btc_prices.sqlx
  external_table_id   = "ext_btc_price_parquet"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "dataform.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "staging_bucket" {
  source     = "../../modules/gcs-bucket"
  project_id = var.project_id
  name       = local.staging_bucket_name
  location   = var.region
}

module "staging_dataset" {
  source      = "../../modules/bq-dataset"
  project_id  = var.project_id
  dataset_id  = local.staging_dataset_id
  location    = var.region
  description = "Raw BTC price parquet landed by the fetch-btc-price Cloud Function."
}

module "curated_dataset" {
  source      = "../../modules/bq-dataset"
  project_id  = var.project_id
  dataset_id  = local.curated_dataset_id
  location    = var.region
  description = "Curated BTC price tables produced by Dataform (definitions/curated_btc_prices.sqlx)."
}

module "external_btc_table" {
  source     = "../../modules/bq-table"
  project_id = var.project_id
  dataset_id = module.staging_dataset.dataset_id
  table_id   = local.external_table_id
  external_data_configuration = {
    source_uris   = ["gs://${local.staging_bucket_name}/staging/*.parquet"]
    source_format = "PARQUET"
  }
}
