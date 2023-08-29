set -x
# Creates GKE autopilot clusters
# Initializes APIS, sets up the Google Cloud Deploy pipeline
# bail if PROJECT_ID is not set
if [[ -z "${PROJECT_ID}" ]]; then
  echo "The value of PROJECT_ID is not set. Be sure to run export PROJECT_ID=YOUR-PROJECT first"
  exit 1
fi

echo "creating binauthz policy..."
sed -i "s/project-id-here/${PROJECT_ID}/" binauthz-policy.yaml
gcloud beta container binauthz policy create build-as-code \
    --platform=gke \
    --policy-file=binauthz-policy.yaml \
    --project=$PROJECT_ID

echo "creating staging cluster..."
gcloud beta container --project "$PROJECT_ID" clusters create "staging" \
  --region "us-central1" \
  --machine-type "e2-medium" \
  --num-nodes "1" \
  --network "projects/$PROJECT_ID/global/networks/default" \
  --subnetwork "projects/$PROJECT_ID/regions/us-central1/subnetworks/default" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --async

echo "creating 1st production cluster..."
gcloud beta container --project "$PROJECT_ID" clusters create "production-1" \
  --region "us-central1" \
  --machine-type "e2-medium" \
  --num-nodes "3" \
  --network "projects/$PROJECT_ID/global/networks/default" \
  --subnetwork "projects/$PROJECT_ID/regions/us-central1/subnetworks/default" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
  --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
  --async

echo "creating 2nd production cluster..."
gcloud beta container --project "$PROJECT_ID" clusters create "production-2" \
  --region "europe-west1" \
  --machine-type "e2-medium" \
  --num-nodes "3" \
  --network "projects/$PROJECT_ID/global/networks/default" \
  --subnetwork "projects/$PROJECT_ID/regions/europe-west1/subnetworks/default" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
  --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
  --async

echo "creating 3rd production cluster..."
gcloud beta container --project "$PROJECT_ID" clusters create "production-3" \
  --region "asia-northeast1" \
  --machine-type "e2-medium" \
  --num-nodes "3" \
  --network "projects/$PROJECT_ID/global/networks/default" \
  --subnetwork "projects/$PROJECT_ID/regions/asia-northeast1/subnetworks/default" \
  --enable-autoupgrade \
  --enable-autorepair \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0 \
  --binauthz-evaluation-mode=POLICY_BINDINGS_AND_PROJECT_SINGLETON_POLICY_ENFORCE \
  --binauthz-policy-bindings=name=projects/$PROJECT_ID/platforms/gke/policies/build-as-code \
  --async

echo "Creating clusters! Check the UI for progress"