# Examine Billing data with BigQuery — task by task

Manual equivalent of `gsp_bigquery_billing.sh`. Assumes Cloud Shell with the
lab project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The three checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Use BigQuery to import data | 40 |
| 2 | Compose a simple query | 30 |
| 3 | Analyze a large billing dataset with SQL | 30 |

---

## Task 1 — Use BigQuery to import data

### The dataset

```bash
bq --location=US mk --dataset \
    --default_table_expiration_ms=86400000 \
    --description="Billing dataset for lab" \
    $PROJECT_ID:billing_dataset
```

The console's field is **1 days (Default maximum table age)**. The API stores
it in milliseconds, so 1 day is `86400000`.

> The `bq` flag for this is spelled differently between versions
> (`--default_table_expiration` vs `--default_table_expiration_ms`), and the
> unit is easy to get wrong — a 1-day expiry that is read as seconds would
> delete the table out from under you. The script creates the dataset, then
> reads the value back through the API and corrects it if it is not right.

### The table

The sample billing file is an **Avro** file in a public bucket:

```bash
bq load --location=US \
    --source_format=AVRO \
    $PROJECT_ID:billing_dataset.sampleinfotable \
    gs://cloud-training/archinfra/BillingExport-2020-09-18.avro
```

That file is 160 MB and the load takes a minute or two. `bq load` blocks
until the job finishes, so watch the progress rather than assuming it has
hung.

Click **Check my progress** — *Use BigQuery to import data*.

## Task 2 — Examine the table

```bash
bq show --schema --format=prettyjson $PROJECT_ID:billing_dataset.sampleinfotable
bq show $PROJECT_ID:billing_dataset.sampleinfotable
bq query --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) AS total_rows FROM \`$PROJECT_ID.billing_dataset.sampleinfotable\`"
```

## Task 3 — Compose a simple query

```sql
SELECT * FROM `billing_dataset.sampleinfotable`
WHERE cost > 0
```

```bash
bq query --use_legacy_sql=false \
  "SELECT * FROM \`billing_dataset.sampleinfotable\` WHERE cost > 0"
```

Click **Check my progress** — *Compose a simple query*.

> The project ID is optional in a table reference — BigQuery defaults to the
> current project — so `billing_dataset.sampleinfotable` is enough.

## The embedded questions, and their answers

The lab has six knowledge checks. These are the answers, taken from the
billing export the lab ships — the data is fixed, so the numbers are fixed.

| Question | Answer |
|---|---|
| What is the total number of rows in the table? | **415,602** |
| How many rows had cost greater than 0? | **70,765 rows** |
| Which product had the most billing records? | **Compute Engine** — 281,136 records |
| Which product had the most billing records of over $1? | **Cloud Storage** — 17 charges |
| What was the most commonly charged unit of measure? | **Byte-seconds** |
| Which product has the highest total cost? | **Compute Engine** — $2,548.77 |

The other two totals, for reference: Cloud Storage $40.05 and BigQuery $910.73.
Cloud SQL has 10,271 records and BigQuery 39,498 — both far behind Compute
Engine's 281,136.

## Task 4 — Analyze a large billing dataset with SQL

Run each of these. The table has **415,602** rows.

```sql
-- 1. every billing record
SELECT
  billing_account_id,
  project.id,
  project.name,
  service.description,
  currency,
  currency_conversion_rate,
  cost,
  usage.amount,
  usage.pricing_unit
FROM
  `billing_dataset.sampleinfotable`
```

```sql
-- 2. the latest 100 records with a charge
SELECT
  service.description, sku.description, location.country, cost,
  project.id, project.name, currency, currency_conversion_rate,
  usage.amount, usage.unit
FROM `billing_dataset.sampleinfotable`
WHERE cost > 0
ORDER BY usage_end_time DESC
LIMIT 100
```

```sql
-- 3. every charge over 10 dollars
SELECT
  service.description, sku.description, location.country, cost,
  project.id, project.name, currency, currency_conversion_rate,
  usage.amount, usage.unit
FROM `billing_dataset.sampleinfotable`
WHERE cost > 10
```

```sql
-- 4. the product with the most records
SELECT service.description, COUNT(*) AS billing_records
FROM `billing_dataset.sampleinfotable`
GROUP BY service.description
ORDER BY billing_records DESC
```

```sql
-- 5. the most used product costing more than 1 dollar
SELECT service.description, COUNT(*) AS billing_records
FROM `billing_dataset.sampleinfotable`
WHERE cost > 1
GROUP BY service.description
ORDER BY billing_records DESC
```

```sql
-- 6. the most commonly charged unit of measure
SELECT usage.unit, COUNT(*) AS billing_records
FROM `billing_dataset.sampleinfotable`
WHERE cost > 0
GROUP BY usage.unit
ORDER BY billing_records DESC
```

```sql
-- 7. the product with the highest aggregate cost
SELECT service.description, ROUND(SUM(cost),2) AS total_cost
FROM `billing_dataset.sampleinfotable`
GROUP BY service.description
ORDER BY total_cost DESC
```

Click **Check my progress** — *Analyze a large billing dataset with SQL*.

> The checkpoints are scored from the **query job history**, so the queries
> have to actually run — pasting them into the console is what the lab does,
> and running them with `bq query` lands in the same history.

## Clean up

```bash
bq rm -f -t $PROJECT_ID:billing_dataset.sampleinfotable
bq rm -f -d $PROJECT_ID:billing_dataset
```
