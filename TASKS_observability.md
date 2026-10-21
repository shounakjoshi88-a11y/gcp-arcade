# Monitor Resources with Google Cloud Observability — task by task

Manual equivalent of `gsp_observability.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The lab pre-creates three VMs — `nginxstack-1`, `nginxstack-2` and
`nginxstack-3` — and the resource group and the uptime check are built around
them.

The four checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create custom dashboard | 25 |
| 2 | Create alerting policies | 25 |
| 3 | Create Resource Group | 25 |
| 4 | Create uptime check | 25 |

---

## Task 1 — Verify the resources

```bash
gcloud compute instances list --filter="name ~ 'nginxstack'" \
    --format="table(name,zone,status)"
```

## Task 2 — Create custom dashboards

```bash
cat > /tmp/dashboard.json <<'EOF'
{
  "displayName": "My Dashboard",
  "gridLayout": {
    "columns": "2",
    "widgets": [
      {
        "title": "My Chart",
        "xyChart": {
          "dataSets": [
            {
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              },
              "plotType": "LINE"
            }
          ]
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json
```

> **The layout has to be `gridLayout`.** A dashboard with a different layout
> is accepted by the API, shows up in the console, and still scores **0** —
> the console form gives you no hint that the layout matters. This is the
> single most common way to lose points on this lab.

## Task 3 — Alerting policies

### The notification channel

```bash
gcloud beta monitoring channels create \
    --display-name="Lab Notification Channel" \
    --type="email" \
    --channel-labels="email_address=YOUR_EMAIL" \
    --format="value(name)"
```

### The policy

Two conditions, both **above 20**, with a 1 minute rolling window, and
**all** of them met before the policy fires:

```bash
cat > /tmp/policy.json <<'EOF'
{
  "displayName": "My Alert Policy",
  "combiner": "AND",
  "conditions": [
    {
      "displayName": "VM Instance - CPU usage",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/usage_time\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_RATE" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    },
    {
      "displayName": "VM Instance - CPU utilization",
      "conditionThreshold": {
        "filter": "resource.type = \"gce_instance\" AND metric.type = \"compute.googleapis.com/instance/cpu/utilization\"",
        "aggregations": [
          { "alignmentPeriod": "60s", "perSeriesAligner": "ALIGN_MEAN" }
        ],
        "comparison": "COMPARISON_GT",
        "thresholdValue": 20,
        "duration": "0s",
        "trigger": { "count": 1 }
      }
    }
  ],
  "notificationChannels": [ "CHANNEL_NAME" ],
  "enabled": true
}
EOF

gcloud alpha monitoring policies create --policy-from-file=/tmp/policy.json
```

## Task 4 — Resource groups

There is no `gcloud` command for groups, so the API:

```bash
TOKEN=$(gcloud auth print-access-token)

curl -s -X POST \
    "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/groups" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "displayName": "VM instances",
      "filter": "resource.type = \"gce_instance\" AND resource.metadata.name = starts_with(\"nginx\")"
    }'
```

> **The group has to actually MATCH the VMs.** A group with a plausible
> looking filter and an empty member list does not score. Check the members:
>
> ```bash
> curl -s -H "Authorization: Bearer $TOKEN" \
>   "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/groups/GROUP_ID/members"
> ```
>
> The script tries the filter forms in turn and keeps the first one that
> actually matches:
>
> 1. `resource.type = "gce_instance" AND resource.metadata.name = starts_with("nginx")`
> 2. `resource.type = "gce_instance" AND metadata.system_labels.name = starts_with("nginx")`
> 3. `resource.type = "gce_instance" AND resource.metadata.name = has_substring("nginx")`
> 4. `resource.metadata.name = has_substring("nginx")`

## Task 5 — Uptime monitoring

```bash
gcloud monitoring uptime create "My Uptime check" \
    --group-id=GROUP_ID \
    --group-type=gce-instance \
    --protocol=http --port=80 --path=/ --period=60
```

`--group-type=gce-instance` is the console's **Resource Type: Instance**, and
`--group-id` is the **Applies To: Group** setting.

The check takes a few minutes to become active.

## Task 6 — Disable the alert

The lab asks you to turn the alerting policy off at the end:

```bash
gcloud alpha monitoring policies update POLICY_NAME --no-enabled
```

---

## Clean up

```bash
gcloud monitoring uptime delete "My Uptime check"
gcloud alpha monitoring policies delete POLICY_NAME
gcloud beta monitoring channels delete CHANNEL_NAME
gcloud monitoring dashboards delete DASHBOARD_NAME
curl -s -X DELETE -H "Authorization: Bearer $TOKEN" \
  "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/groups/GROUP_NAME"
```
