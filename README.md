# Demo: Devops Best Practices

This repo is a fork of https://github.com/nateaveryg/pop-kustomize which is meant to demonstrate
setting up a project in GCP that follows devops best practices.

The demo will be used to display:
- [x] Cloud workstations
- [x] GCB triggering
- [x] Build and push to AR
- [x] Cloud Deploy deploy to test
- [x] Cloud Deploy promotion across environments
- [x] Image scanning
- [x] Cloud Build security insights
- [x] Provenance generation
- [x] Cloud Deploy security insights
- [x] Cloud Deploy canary deployment w/ verification
- [x] Cloud Deploy with parallel deployment
- [x] Binauthz gating of deployment
- [x] Local development w/ minikube

## Setup tutorial

## Setup: enable APIs

Set the PROJECT_ID environment variable. This variable will be used in forthcoming steps.

```bash
export PROJECT_ID=<walkthrough-project-id/>
# sets the current project for gcloud
gcloud config set project $PROJECT_ID
# Enables various APIs you'll need
gcloud services enable \
  container.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  clouddeploy.googleapis.com \
  cloudresourcemanager.googleapis.com \
  secretmanager.googleapis.com \
  containeranalysis.googleapis.com \
  containerscanning.googleapis.com \
  binaryauthorization.googleapis.com
```

## Add Deployment

### Setup AR repo to push images to


Create the repository:
```bash
gcloud artifacts repositories create pop-stats \
  --location=us-central1 \
  --repository-format=docker \
  --project=$PROJECT_ID
```

### Create GKE clusters

Create the GKE clusters:

```bash
./bootstrap/gke-cluster-init.sh
```

Verify that they were created in the [GKE UI](https://console.cloud.google.com/kubernetes/list/overview)

### Build up the pipeline

```bash
# customize the clouddeploy.yamls
export IDENTIFIER=$(date +%s)
sed -i "s/project-id-here/${PROJECT_ID}/" clouddeploy*.yaml
sed -i "s/identifier/${IDENTIFIER}/" clouddeploy*.yaml
```

View Google Cloud Deploy pipelines in the:
[Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines)

#### 1. Just one cluster, with a canary

```bash
gcloud deploy apply --file clouddeploy-1.yaml --region=us-central1 --project=$PROJECT_ID

# Need to push a canary deployment through or it will skip the first time
export RELEASE=rel-$(date +%s)
gcloud deploy releases create ${RELEASE} \
  --delivery-pipeline pop-stats-pipeline-${IDENTIFIER} \
  --region us-central1 \
  --images pop-stats=us-central1-docker.pkg.dev/catw-farm/pop-stats/pop-stats@sha256:15c2aa214cb50f9d374f933a5994006e0ba85df2fc3c00fb478ecb81f8b162ba
```

#### 2. Redundancy w/ multiple production targets and parallel deployment

```bash
gcloud deploy apply --file clouddeploy-2.yaml --region=us-central1 --project=$PROJECT_ID
```

Try it out with the bad image:

```bash
export RELEASE=bad-$(date +%s)
gcloud deploy releases create ${RELEASE} \
  --delivery-pipeline pop-stats-pipeline-${IDENTIFIER} \
  --region us-central1 \
  popstats=us-central1-docker.pkg.dev/catw-farm/pop-stats/pop-stats:dd9023d13ff0aef4891ac1d28fe90417b128d2da
```
```
#### 3. Add staging environment

```bash
gcloud deploy apply --file clouddeploy-3.yaml --region=us-central1 --project=$PROJECT_ID
```

### Setup a Cloud Build trigger to deploy on merge to main

#### IAM and service account setup

You must give Cloud Build explicit permission to trigger a Google Cloud Deploy release.
1. Read the [docs](https://cloud.google.com/deploy/docs/integrating-ci)
2. Navigate to [IAM](https://console.cloud.google.com/iam-admin/iam)
  * Check "Include Google-provided role grants"
  * Locate the service account named "Cloud Build service account"
3. Add these two roles
  * Cloud Deploy Releaser
  * Service Account User
  * Making "gcloud artifacts docker images describe" work:
    * Container Analysis Admin + service agent (probably overkill?)
    * Artifact registry reader (???)

You must give the service account that runs your kubernetes workloads
permission to pull containers from artifact registry:
```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/artifactregistry.reader"

# (TODO: why)
# add the Kubernetes developer permission:
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/container.developer"

# (TODO: why)
# add the clouddeploy.jobRunner role to your compute service account
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member=serviceAccount:$(gcloud projects describe $PROJECT_ID \
    --format="value(projectNumber)")-compute@developer.gserviceaccount.com \
    --role="roles/clouddeploy.jobRunner"
```

## Turn on automated container vulnerability analysis
Google Cloud Container Analysis can be set to automatically scan for vulnerabilities on push (see [pricing](https://cloud.google.com/container-analysis/pricing)). 

Enable Container Analysis API for automated scanning:

```bash
gcloud services enable containerscanning.googleapis.com --project=$PROJECT_ID
```

You can now view the vulnerabilities of each image in artifact registry
(e.g. `https://console.cloud.google.com/artifacts/docker/<your project>/<your region>/pop-stats/pop-stats`).

Images are scanned when built, so previously built images will not have vulnerabilities
listed. Open a PR to trigger a build and the newly built image will be scanned.

## Add CI

### Setup a Cloud Build trigger on PRs

Configure Cloud Build to run each time a change is pushed to the main branch. To do this, add a Trigger in Cloud Build:
  1. Follow https://cloud.google.com/build/docs/automating-builds/github/connect-repo-github to connect
     your GitHub repo
  2. Follow https://cloud.google.com/build/docs/automating-builds/github/build-repos-from-github?generation=2nd-gen to setup triggering:
    * Setup PR triggering to run cloudbuild.yaml

Open a PR to create a Cloud Deploy release and deploy it to the
the `test` environment.  You can see the progress via the
[Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines).

## Promote the release

In the [Google Cloud Deploy UI](https://console.cloud.google.com/deploy/delivery-pipelines),
you can promote the release from test to staging, and from staging to prod (with a manual
approval step in between).

## Security insights

* View Cloud Build security insights via the Cloud Build history view: https://cloud.google.com/build/docs/view-build-security-insights
* View Cloud Deploy security insights via the release artifacts view: https://cloud.google.com/deploy/docs/securing/security-insights

## binauthz gating

### Create binauthz policy

```bash
# customize the clouddeploy.yaml 
sed -i "s/project-id-here/${PROJECT_ID}/" binauthz-policy.yaml
# create the policy
gcloud beta container binauthz policy create build-as-code \
    --platform=gke \
    --policy-file=binauthz-policy.yaml \
    --project=$PROJECT_ID
gcloud beta container clusters update prodcluster1 \
    --location=us-central1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
    --project=$PROJECT_ID
gcloud beta container clusters update prodcluster2 \
    --location=europe-west1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
    --project=$PROJECT_ID
gcloud beta container clusters update prodcluster3 \
    --location=asia-northeast1 \
    --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
    --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
    --project=$PROJECT_ID
```

### Make sure it works

The binauthz policy should prevent the following scenarios from succeeding:
* Pushing an image built locally
* Building an image using an inline cloudbuild.yaml

Build and push an image locally:

```bash
# build the image
export LAZY=lazy-$(date +%s)
export IMAGE="us-central1-docker.pkg.dev/$PROJECT_ID/pop-stats/pop-stats:$LAZY"
docker build app/ -t $IMAGE -f app/Dockerfile

# push the image
gcloud auth configure-docker us-central1-docker.pkg.dev
docker push $IMAGE

# start a pod in a production cluster that uses the image
gcloud container clusters get-credentials prodcluster1 --region us-central1 --project $PROJECT_ID
kubectl run sneakypod --image=${IMAGE}
```

You can also try using an inline cloudbuild.yaml by creating a manual trigger
using the same cloudbuild.yaml in this repo.

You will see the audit logs show up several hours later:

```bash
gcloud logging read \
     --order="desc" \
     --freshness=7d \
     --project=$PROJECT_ID \
    'logName:"binaryauthorization.googleapis.com%2Fcontinuous_validation" "build-as-code"'
```

## Tear down

To remove the three running GKE clusters, run:
```bash
. ./bootstrap/gke-cluster-delete.sh
```

## Local dev (optional)

To run this app locally, start minikube:
```bash 
minikube start
```

From the pop-kustomize directory, run:
```bash
skaffold dev
```

The default skaffold settings use the "dev" Kustomize overlay. Once running, you can make file changes and observe the rebuilding of the container and redeployment. Use Ctrl-C to stop the Skaffold process.

To test the staging overlays/profile run:
```bash
skaffold dev --profile staging
```

To test the staging overlays/profile locally, run:
```bash
skaffold dev --profile prod
```
## About the Sample app - Population stats

Simple web app that pulls population and flag data based on country query.

Population data from restcountries.com API.

Feedback and contributions welcomed!
