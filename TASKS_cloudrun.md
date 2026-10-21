# Hello Cloud Run — task by task

Manual equivalent of `gsp_cloudrun.sh`. Assumes Cloud Shell with the lab
project active.

```bash
export PROJECT_ID=$(gcloud config get-value project)
export LOCATION=REGION      # the region on your lab setup panel
```

---

## Task 1 — Enable the APIs and set the region

```bash
gcloud services enable run.googleapis.com artifactregistry.googleapis.com
gcloud config set compute/region $LOCATION
```

## Task 2 — Write the sample application

Create a folder and two files.

```bash
mkdir -p helloworld && cd helloworld
```

`package.json`:

```json
{
  "name": "helloworld",
  "description": "Simple hello world sample in Node",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "author": "Google LLC",
  "license": "Apache-2.0",
  "dependencies": {
    "express": "^4.17.1"
  }
}
```

`index.js`:

```javascript
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  const name = process.env.NAME || 'World';
  res.send(`Hello ${name}!`);
});

app.listen(port, () => {
  console.log(`helloworld: listening on port ${port}`);
});
```

## Task 3 — Create an Artifact Registry repository

```bash
gcloud artifacts repositories create my-repository \
    --repository-format=docker \
    --location=$LOCATION \
    --description="Docker repository"

gcloud auth configure-docker $LOCATION-docker.pkg.dev
```

The second command points your local `docker` at Artifact Registry so you can
pull and push without a key file.

## Task 4 — Containerize the app and upload it

`Dockerfile` — use the base image your lab page names:

```dockerfile
FROM node:20

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm install --only=production

COPY . ./

CMD [ "npm", "start" ]
```

Build and push it. Cloud Build does the work, so you don't need a local
Docker build:

```bash
gcloud builds submit \
    --tag $LOCATION-docker.pkg.dev/$PROJECT_ID/my-repository/helloworld
```

Then run it locally to check it answers:

```bash
docker run -d -p 8080:8080 $LOCATION-docker.pkg.dev/$PROJECT_ID/my-repository/helloworld
curl http://localhost:8080/
docker rm -f $(docker ps -q)
```

It should print `Hello World!`.

## Task 5 — Deploy to Cloud Run

```bash
gcloud run deploy helloworld \
    --image $LOCATION-docker.pkg.dev/$PROJECT_ID/my-repository/helloworld \
    --allow-unauthenticated \
    --region=$LOCATION
```

Then check it:

```bash
gcloud run services describe helloworld --region=$LOCATION --format="value(status.url)"
curl $(gcloud run services describe helloworld --region=$LOCATION --format="value(status.url)")
```

### If the deploy seems to hang

It is not hung. The **first** revision has to pull the container image out of
Artifact Registry before it can become ready, and that usually takes 3–5
minutes. Watch it in a second tab:

```bash
gcloud run services describe helloworld --region=$LOCATION \
    --format="value(status.latestReadyRevisionName,status.url)"
```

or in the console under **Cloud Run → Services**.

If you do interrupt it, re-running `gcloud run deploy` is safe — it creates a
new revision.

## Clean up

```bash
gcloud run services delete helloworld --region=$LOCATION --quiet
gcloud artifacts repositories delete my-repository --quiet
gcloud container images delete \
    $LOCATION-docker.pkg.dev/$PROJECT_ID/my-repository/hel