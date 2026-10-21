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

## The knowledge-check questions, and their answers

| Question | Answer |
|---|---|
| Why is monitoring important to Google? | **It is at the base of site reliability which incorporates aspects of software engineering and applies that to operations whose goals are to create ultra-scalable and highly reliable software systems.** |
| Which strategy effectively reduces alert fatigue? | **Customize your alerts to the audience need**, **use multiple notification channels so you avoid a single point of failure**, and **configure alerting on symptoms and not necessarily causes**. Never *report all noise to ensure all data points are presented* — that is the one that causes fatigue. |
| Select all valid targets for Cloud Monitoring uptime alert notifications. | **webhook**, **email**, **Pub/sub**, **3rd party service** and **SMS**. Not *EC2 service* — that is a resource type, not a notification target. |

The third one matches the Cloud Monitoring API exactly. The channel types it
accepts are:

```bash
gcloud beta monitoring channel-descriptors list --format='value(type)'
# campfire, email, google_chat, hipchat, pagerduty, pubsub, slack, sms,
# webhook_basicauth, webhook_tokenauth
```

**EC2 service** is not on that list, which is what makes it the odd one out.

> The lab's own source asks the alert-fatigue question the other way round —
> *"What is **not** a recommended best practice for alerts?"* — and marks
> *Report all noise to ensure all data points are presented*. The positive
> form flips the pick to the other three. Both forms agree that reporting all
> the noise is the wrong answer.

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
  "dashboardFilters": [],
  "labels": {},
  "mosaicLayout": {
    "columns": 48,
    "tiles": [
      {
        "xPos": 0,
        "yPos": 0,
        "width": 24,
        "height": 16,
        "widget": {
          "title": "My Chart",
          "xyChart": {
            "chartOptions": { "mode": "COLOR" },
            "dataSets": [
              {
                "minAlignmentPeriod": "60s",
                "plotType": "LINE",
                "targetAxis": "Y1",
                "timeSeriesQuery": {
                  "apiSource": "DEFAULT_CLOUD",
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "groupByFields": [],
                      "perSeriesAligner": "ALIGN_MEAN"
                    },
                    "filter": "metric.type=\"compute.googleapis.com/instance/cpu/utilization\" resource.type=\"gce_instance\"",
                    "secondaryAggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_NONE",
                      "groupByFields": [],
                      "perSeriesAligner": "ALIGN_NONE"
                    }
                  },
                  "outputFullDuration": false
                }
              }
            ],
            "thresholds": [],
            "yAxis": { "label": "", "scale": "LINEAR" }
          }
        }
      }
    ]
  }
}
EOF

gcloud monitoring dashboards create --config-from-file=/tmp/dashboard.json
```

> **The dashboard has to be a classic one — a `mosaicLayout` with
> `tiles`.** A `gridLayout` dashboard is accepted by the API, shows up in the
> console, and still scores **0**, because the lab looks for the chart in the
> classic shape. The console form gives you no hint that the layout matters.
>
> The script deletes any dashboard with that name and creates it again from
> scratch every time, in the shape the console itself produces.

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
      "filter": "resource.metadata.name = has_substring(\"nginx\")"
    }'
```

> **The filter has to be the one the console builds.** The lab's criterion
> is *Value: nginx* — in the console's **Contains** operator — and the console
> turns that into exactly:
>
> ```
> resource.metadata.name = has_substring("nginx")
> ```
>
> The lab grades the group's **configuration** — a group with any other filter
> scores **0**, even though the API accepts it and it shows up in the console.
> Note what is *not* in it: no `resource.type = "gce_instance" AND` prefix,
> and it is `has_substring`, not `starts_with`. Use that filter, exactly.
>
> ```bash
> curl -s -X POST \
>     "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/groups" \
>     -H "Authorization: Bearer $TOKEN" \
>     -H "Content-Type: application/json" \
>     -d '{
>       "displayName": "VM instances",
>       "filter": "resource.metadata.name = has_substring(\"nginx\")"
>     }'
> ```
>
> **The member list fills in in the background.** Right after you create a
> group it can have no members for a minute or two, because the membership is
> evaluated periodically. That is normal, and it does not affect the
> checkpoint — the checkpoint looks at the group's configuration. Check it
> whenever you like:
>
> ```bash
> curl -s -H "Authorization: Bearer $TOKEN" \
>   "https://monitoring.googleapis.com/v3/projects/$PROJECT_ID/groups/GROUP_ID/members"
> ```

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
