# Mirrors streaming-crypto-gcp-analytics/deploy.sh
# NOTE: the Dataflow job itself is intentionally NOT managed here — it's a
# long-running streaming job launched manually (see that repo's README).
# This stack only owns the infra it reads/writes.

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
    prefix = "streaming-analytics"
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

locals {
  topic_id        = "crypto-prices"
  subscription_id = "crypto-prices-sub"
  dataset_id      = "crypto_analytics"
  raw_table_id    = "crypto_prices_raw"
  window_table_id = "crypto_price_windows"
  bucket_name     = "${var.project_id}-dataflow"
}

resource "google_project_service" "apis" {
  for_each = toset([
    "pubsub.googleapis.com",
    "dataflow.googleapis.com",
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "compute.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

module "crypto_prices_topic" {
  source               = "../../modules/pubsub-topic"
  project_id           = var.project_id
  topic_name           = local.topic_id
  subscription_name    = local.subscription_id
  ack_deadline_seconds = 10 # matches the existing subscription's real value
}

module "dataflow_bucket" {
  source                      = "../../modules/gcs-bucket"
  project_id                  = var.project_id
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = false # matches the bucket's existing real setting
}

module "crypto_analytics_dataset" {
  source     = "../../modules/bq-dataset"
  project_id = var.project_id
  dataset_id = local.dataset_id
  location   = "US"
}

module "raw_table" {
  source     = "../../modules/bq-table"
  project_id = var.project_id
  dataset_id = module.crypto_analytics_dataset.dataset_id
  table_id   = local.raw_table_id
  schema     = file("${path.module}/schemas/schema_raw.json")
}

module "windows_table" {
  source     = "../../modules/bq-table"
  project_id = var.project_id
  dataset_id = module.crypto_analytics_dataset.dataset_id
  table_id   = local.window_table_id
  schema     = file("${path.module}/schemas/schema_windows.json")
}
