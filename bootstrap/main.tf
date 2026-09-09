# One-time setup, run manually (`terraform apply` from this directory with
# your own gcloud user credentials) BEFORE any stack in ../stacks can use its
# GCS backend or before GitHub Actions can authenticate.
#
# Deliberately kept out of the auto-apply CI pipeline and out of the shared
# remote state: this creates the state bucket and the CI identity, so it
# can't depend on either. State for this config stays local
# (bootstrap/terraform.tfstate) — treat that file as sensitive-ish (it
# contains resource IDs, not secrets) and don't commit it if it appears;
# .gitignore below covers it.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

variable "project_id" {
  type    = string
  default = "crypto-etl-project-465203"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "github_org" {
  description = "GitHub org or username that owns the gcp-infra repo, e.g. \"your-username\"."
  type        = string
}

variable "github_repo" {
  description = "Repo name, e.g. \"gcp-infra\"."
  type        = string
  default     = "gcp-infra"
}

# Workload Identity Federation depends on these — iam.googleapis.com is
# usually already on, but iamcredentials/sts often aren't enabled by
# default and WIF token exchange fails without them.
resource "google_project_service" "wif_apis" {
  for_each = toset([
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Terraform state bucket, shared by every stack's `backend "gcs"` block ---
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  versioning {
    enabled = true # so a bad apply's state is recoverable
  }
}

# --- Workload Identity Federation: lets GitHub Actions authenticate to GCP
#     without a downloaded service account JSON key living in repo secrets ---
resource "google_iam_workload_identity_pool" "github" {
  depends_on                = [google_project_service.wif_apis]
  project                   = var.project_id
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id         = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                      = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Restrict to this repo only — without this, ANY GitHub repo could mint
  # tokens impersonating the CI service account below.
  attribute_condition = "assertion.repository == \"${var.github_org}/${var.github_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci" {
  project      = var.project_id
  account_id   = "gcp-infra-ci"
  display_name = "gcp-infra Terraform CI (GitHub Actions)"
}

resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.ci.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# Least-privilege for what these three stacks actually manage. Tighten
# further with custom roles once the resource set stabilizes.
resource "google_project_iam_member" "ci_roles" {
  for_each = toset([
    "roles/storage.admin",
    "roles/bigquery.admin",
    "roles/pubsub.admin",
    "roles/serviceusage.serviceUsageAdmin", # for google_project_service
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci.email}"
}

output "workload_identity_provider" {
  description = "Value for the workload_identity_provider input in the GitHub Actions workflow."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "ci_service_account_email" {
  value = google_service_account.ci.email
}

output "tfstate_bucket" {
  value = google_storage_bucket.tfstate.name
}
