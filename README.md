# gcp-infra

Terraform for the GCP resources behind three pipelines, all in project
`crypto-etl-project-465203`:

- [crypto-price-etl-gcp](../crypto-price-etl-gcp) — Cloud Function → GCS → BigQuery (Dataform)
- [streaming-crypto-gcp-analytics](../streaming-crypto-gcp-analytics) — Pub/Sub → Dataflow → BigQuery
- [flatten-nested-json-dataproc](../flatten-nested-json-dataproc) — GCS → Dataproc Serverless → BigQuery

Each pipeline is a separate **stack** under `stacks/`, with its own Terraform
state. A change to one pipeline's config only plans/applies that stack — see
`.github/workflows/terraform.yml`.

## What's deliberately *not* here

- **Cloud Function code/deploy** (crypto-price-etl-gcp) — stays on its
  existing `cloudbuild.yaml`, which deploys the function on every push. This
  repo only manages the bucket and BigQuery datasets around it.
- **The Dataflow job** (streaming-crypto-gcp-analytics) — it's a long-running
  streaming job launched by hand, not standing infra.
- **Dataproc Serverless batch submissions** (flatten-nested-json-dataproc) —
  one-off job runs, not standing infra.
- **Dataform's own bookkeeping datasets** (`dataform`, `dataform_assertions`
  from `workflow_settings.yaml`) — Dataform manages those itself.

Terraform owns the durable data-plane infra (buckets, datasets, tables,
topics) that these deploys/jobs read and write.

## Things to confirm before applying — found while scaffolding

1. **`stacks/flatten-json` bucket names are placeholders.** That repo's
   `scripts/config.sh` is gitignored and wasn't present locally, so
   `data_bucket_name` / `staging_bucket_name` follow the naming convention
   from `config.sh.example` but aren't confirmed. Check your real
   `config.sh` and update the variable defaults (or pass `-var`) before
   running `terraform plan` on this stack — otherwise it'll try to create
   new buckets alongside whatever you actually named them.
2. **crypto-price-etl-gcp has two conflicting Cloud Function specs**:
   `cloudbuild.yaml` says `--runtime=python310`, gen1-style deploy;
   `deploy/deploy.yaml` says `python311`, gen2, 256MiB, 60s timeout. Since
   the function isn't managed here, this doesn't block anything in this
   repo, but worth reconciling in that repo separately.
3. **Existing resources need `terraform import`, not `apply`, first.** The
   bucket `crypto-etl-bucket-af`, dataset `staging_crypto`, the
   `crypto_analytics` dataset + its two tables, and the `crypto-prices`
   topic/subscription already exist and (may) hold real data. Run the
   import commands below *before* the first `apply` on each stack, or
   Terraform will fail on "already exists" — or worse, if a name ever
   drifts, try to recreate something with real data in it.

## One-time bootstrap (run manually, not via CI)

```
cd bootstrap
terraform init
terraform apply -var="github_org=<your-github-username>"
```

This creates the shared Terraform state bucket
(`crypto-etl-project-465203-tfstate`) and a Workload Identity Federation
setup so GitHub Actions can authenticate without a downloaded service
account key. Take the two outputs and set them as **repo variables** (not
secrets — they aren't sensitive) in the `gcp-infra` GitHub repo:

- `WIF_PROVIDER` ← `workload_identity_provider` output
- `CI_SERVICE_ACCOUNT_EMAIL` ← `ci_service_account_email` output

## Adopting existing resources

From each stack directory, after `terraform init`:

```
# stacks/crypto-price-etl
terraform import module.staging_bucket.google_storage_bucket.this crypto-etl-bucket-af
terraform import module.staging_dataset.google_bigquery_dataset.this crypto-etl-project-465203:staging_crypto

# stacks/streaming-analytics
terraform import module.dataflow_bucket.google_storage_bucket.this crypto-etl-project-465203-dataflow
terraform import module.crypto_analytics_dataset.google_bigquery_dataset.this crypto-etl-project-465203:crypto_analytics
terraform import module.raw_table.google_bigquery_table.this crypto-etl-project-465203:crypto_analytics.crypto_prices_raw
terraform import module.windows_table.google_bigquery_table.this crypto-etl-project-465203:crypto_analytics.crypto_price_windows
terraform import module.crypto_prices_topic.google_pubsub_topic.this projects/crypto-etl-project-465203/topics/crypto-prices
```

After each import, run `terraform plan` and check the diff is empty (or only
adds fields you're fine with) before merging — an import that shows a
destructive diff means the module doesn't match reality yet and needs a
tweak, not an apply.

Anything not listed above (the curated/openfda datasets, the flatten-json
buckets) doesn't exist yet as far as I could tell from the repos — those
would be created fresh by `apply`, not imported.

## Safety net for auto-apply on merge

Every BigQuery dataset and table module sets `lifecycle { prevent_destroy =
true }`. A PR that would destroy or force-replace one of them fails at
`apply` instead of silently deleting real data — you'll see it in the
`terraform plan` output on the PR first either way.
