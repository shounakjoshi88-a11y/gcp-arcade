# Cloud Storage and Cloud SQL — task by task

Manual equivalent of `gsp_storagesql.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
```

---

## Task 2 — Deploy a web server VM instance

```bash
gcloud compute instances create bloghost \
    --zone=ZONE \
    --machine-type=e2-standard-2 \
    --image-family=debian-12 \
    --image-project=debian-cloud \
    --tags=http-server \
    --metadata-from-file=startup-script=startup.sh
```

`startup.sh`:

```bash
#!/bin/bash
apt-get install apache2 php php-mysql -y
service apache2 restart
```

Note the console's **Allow HTTP traffic** tick box is the `http-server` network
tag plus the `default-allow-http` firewall rule:

```bash
gcloud compute firewall-rules create default-allow-http \
    --network=default --allow=tcp:80 --source-ranges=0.0.0.0/0
```

## Task 3 — Create a Cloud Storage bucket

```bash
export LOCATION=US   # or EU, or ASIA - whichever is closest to your lab region

gcloud storage buckets create -l $LOCATION gs://$PROJECT_ID

gcloud storage cp gs://cloud-training/gcpfci/my-excellent-blog.png my-excellent-blog.png
gcloud storage cp my-excellent-blog.png gs://$PROJECT_ID/my-excellent-blog.png

gsutil acl ch -u allUsers:R gs://$PROJECT_ID/my-excellent-blog.png
```

## Task 4 — Create the Cloud SQL instance

```bash
gcloud sql instances create blog-db \
    --database-version=MYSQL_8_0 \
    --edition=ENTERPRISE \
    --tier=db-f1-micro \
    --region=REGION --zone=ZONE \
    --root-password='Passw0rd1!' \
    --assign-ip \
    --authorized-networks="web front end=VM_EXTERNAL_IP/32" \
    --no-require-ssl

gcloud sql users create blogdbuser --instance=blog-db --password='Passw0rd1!'
```

The authorised network needs the VM's **external** IP with `/32` — not the
internal one.

If your gcloud does not accept `--no-require-ssl`, create the instance without
it and then turn it off:

```bash
gcloud sql instances patch blog-db --no-require-ssl
```

## Task 5 — Point the PHP page at Cloud SQL

```bash
gcloud compute scp index.php bloghost:/var/www/html/index.php --zone=ZONE
gcloud compute ssh bloghost --zone=ZONE --command="sudo service apache2 restart"
```

`index.php` — the `$dbserver` value is the Cloud SQL instance's **public** IP
and `$dbpassword` is `Passw0rd1!`:

```php
<html>
<head><title>Welcome to my excellent blog</title></head>
<body>
<h1>Welcome to my excellent blog</h1>
<?php
 $dbserver = "CLOUDSQL_IP";
$dbuser = "blogdbuser";
$dbpassword = "Passw0rd1!";
 try {
  $conn = new PDO("mysql:host=$dbserver;dbname=mysql", $dbuser, $dbpassword);
  $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  echo "Connected successfully";
} catch(PDOException $e) {
  echo "Database connection failed:: " . $e->getMessage();
}

?>
</body></html>
```

## Task 6 — Show the Cloud Storage image on the page

Add this line immediately **before** the `<h1>` line, using the object's
public URL:

```html
 <img src='https://storage.googleapis.com/YOUR_PROJECT/my-excellent-blog.png'>
```

```bash
gcloud compute scp index.php bloghost:/var/www/html/index.php --zone=ZONE
gcloud compute ssh bloghost --zone=ZONE --command="sudo service apache2 restart"
```

## Clean up

```bash
gcloud sql instances delete blog-db --quiet
gcloud compute instances delete bloghost --zone=ZONE --quiet
gcloud storage rm -r gs://