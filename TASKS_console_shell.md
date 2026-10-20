# Explore the Google Cloud Console and Cloud Shell — task by task

Manual equivalent of `gsp_console_shell.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

The three checkpoints are:

| # | Checkpoint | Points |
|---|---|---|
| 1 | Create a bucket using the GCP Console | 30 |
| 2 | Create a bucket using Cloud Shell | 30 |
| 3 | Upload a file to Storage bucket | 40 |

---

## Task 1 — Create a bucket using the Cloud console

This one has to be done in the console — the lab grades it as a **console**
creation, so a `gcloud storage buckets create` will not do.

1. Open the pre-filled console page:

   ```bash
   echo "https://console.cloud.google.com/storage/create-bucket?project=$PROJECT_ID"
   ```

2. For **Name**, type a globally unique bucket name. The project ID works:

   ```bash
   echo $PROJECT_ID
   ```

3. Leave everything else at its default and click **Create**.
4. If it says *Public access will be prevented*, click **Confirm**.

Click **Check my progress**.

## Task 2 — Access Cloud Shell

> If you are running the script, **skip this task for now**. Closing Cloud
> Shell resets the VM and kills the script. Task 2 has no checkpoint, so you
> can close and reopen Cloud Shell after the script finishes.

Explore the four buttons on the right of the Cloud Shell toolbar — minimize,
restore/maximize, open in a new window, and close terminal — then close Cloud
Shell.

### The multiple-choice question in task 2

*Select the features and capabilities provided by Cloud Shell. (Select all that
apply.)*

| Option | Answer |
|---|---|
| A command-line tool that requires you to install Cloud SDK | **No** — the Cloud SDK is pre-installed; the lab says you can work "without having to install the Cloud SDK and other tools on your computer" |
| Command-line access to a free temporary Compute Engine VM | **Yes** |
| 5 GB of persistent disk storage (`$HOME` dir) | **Yes** |
| Built-in authorization for access to resources and instances | **Yes** |

Tick the **last three**. The first option describes the `gcloud` CLI when you
install it on your own machine, not Cloud Shell.

## Task 3 — Create a bucket using Cloud Shell

```bash
gcloud storage buckets create gs://$PROJECT_ID-2
```

The lab suggests appending a `2` to the bucket name you used in the console.

Check it from the console too: **Cloud Storage → Buckets**, then **Refresh**.

Click **Check my progress**.

## Task 4 — Upload a file to Storage bucket

Upload a file from your own machine with the **Upload** button in the Cloud
Shell toolbar (the file lands in `$HOME`), then copy it into a bucket:

```bash
ls
gcloud storage cp my-file.txt gs://$PROJECT_ID-2
```

Quote the name if it has spaces:

```bash
gcloud storage cp 'my file.txt' gs://$PROJECT_ID-2
```

Click **Check my progress**.

## Task 5 — Create a persistent state in Cloud Shell

List the regions and pick one:

```bash
gcloud compute regions list
```

Set the two variables and save them to a file:

```bash
INFRACLASS_REGION=us-central1
INFRACLASS_PROJECT_ID=$PROJECT_ID

mkdir infraclass
touch infraclass/config
echo INFRACLASS_REGION=$INFRACLASS_REGION >> ~/infraclass/config
echo INFRACLASS_PROJECT_ID=$INFRACLASS_PROJECT_ID >> ~/infraclass/config

source infraclass/config
echo $INFRACLASS_PROJECT_ID
```

Close and reopen Cloud Shell — the variables are gone, because the VM was
reset. Then make them survive by sourcing the config file from your profile:

```bash
nano .profile
```

Add this line at the end:

```bash
source infraclass/config
```

`Ctrl+O`, `Enter` to save, `Ctrl+X` to exit. Close and reopen Cloud Shell
again, then:

```bash
echo $INFRACLASS_PROJECT_ID
```

It is still there.

> The profile line only runs in a **login** shell. To check it without
> closing Cloud Shell:
>
> ```bash
> bash -lc 'echo $INFRACLASS_PROJECT_ID'
> ```

## Clean up

```bash
gcloud storage rm -r gs://$PROJECT_ID-2
gcloud storage rm -r gs://$PROJECT_ID
```
