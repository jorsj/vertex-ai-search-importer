#!/bin/bash

# ==============================================================================
# Interactive Deployment Script for Vertex AI Search Importer Cloud Function
#
# This script guides you through deploying a Cloud Function that automatically
# indexes files from a GCS bucket into a Vertex AI Search data store.
# It follows security best practices by creating separate, minimally-privileged
# service accounts for the function and its trigger.
# ==============================================================================

# --- Bash Setup ---
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Style Definitions (for clearer output) ---
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
NC=$(tput sgr0) # No Color

# --- Prerequisite Check ---
if ! command -v gcloud &> /dev/null
then
    echo "${YELLOW}ERROR: The 'gcloud' command-line tool is not installed or not in your PATH.${NC}"
    echo "Please install the Google Cloud SDK and try again: https://cloud.google.com/sdk/install"
    exit 1
fi
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
    echo "${YELLOW}You are not logged into gcloud. Please run 'gcloud auth login' and 'gcloud config set project' first.${NC}"
    exit 1
fi
echo "Running as gcloud user: ${GREEN}${ACTIVE_ACCOUNT}${NC}"
echo ""


# ==============================================================================
# 1. GATHER USER INPUT
# ==============================================================================
echo "${BOLD}Please provide the necessary information for deployment.${NC}"

# Get Project ID, pre-filling with the current gcloud config
CURRENT_PROJECT=$(gcloud config get-value project)
read -p "Enter your Google Cloud Project ID [${CURRENT_PROJECT}]: " YOUR_PROJECT_ID
export YOUR_PROJECT_ID=${YOUR_PROJECT_ID:-$CURRENT_PROJECT}

# Get other required variables
read -p "Enter the GCS bucket name to monitor (e.g., my-source-files): " TRIGGER_BUCKET
read -p "Enter the GCP region for the Cloud Function (e.g., us-central1) [us-central1]: " GCP_REGION
read -p "Enter the location of your Vertex AI data store (e.g., global, us) [global]: " VERTEX_LOCATION
read -p "Enter your Vertex AI Search Data Store ID: " VERTEX_DATA_STORE_ID

# Use default names for resources, which is generally fine
export FUNCTION_NAME="vertex-ai-search-importer"
export FUNCTION_SA_NAME="vertex-importer-sa"
export TRIGGER_SA_NAME="vertex-trigger-invoker-sa"

# Derive bucket region to determine trigger location
echo "Detecting bucket location..."
BUCKET_LOCATION_RAW=$(gcloud storage buckets describe gs://${TRIGGER_BUCKET} --format="value(location)")
export TRIGGER_LOCATION=$(echo "${BUCKET_LOCATION_RAW}" | tr '[:upper:]' '[:lower:]')
echo "Bucket location detected as '${TRIGGER_LOCATION}'. The trigger will be deployed there."

# --- Sanity Checks ---
if [[ -z "$YOUR_PROJECT_ID" || -z "$TRIGGER_BUCKET" || -z "$VERTEX_DATA_STORE_ID" ]]; then
    echo "${YELLOW}ERROR: Project ID, Trigger Bucket, and Data Store ID cannot be empty.${NC}"
    exit 1
fi


# ==============================================================================
# 2. CONFIRMATION
# ==============================================================================
echo ""
echo "${BOLD}--------------------------------------------------${NC}"
echo "${BOLD}Deployment Configuration Summary${NC}"
echo "${BOLD}--------------------------------------------------${NC}"
echo "Project ID:            ${GREEN}${YOUR_PROJECT_ID}${NC}"
echo "GCS Trigger Bucket:    ${GREEN}${TRIGGER_BUCKET}${NC}"
echo ""
echo "Cloud Function Name:   ${GREEN}${FUNCTION_NAME}${NC}"
echo "Cloud Function Region: ${GREEN}${GCP_REGION:-us-central1}${NC}"
echo "Eventarc Trigger Region: ${GREEN}${TRIGGER_LOCATION}${NC}"
echo ""
echo "Vertex AI Location:    ${GREEN}${VERTEX_LOCATION:-global}${NC}"
echo "Vertex AI Data Store:  ${GREEN}${VERTEX_DATA_STORE_ID}${NC}"
echo ""
echo "Function Service Acct: ${GREEN}${FUNCTION_SA_NAME}${NC}"
echo "Trigger Service Acct:  ${GREEN}${TRIGGER_SA_NAME}${NC}"
echo "${BOLD}--------------------------------------------------${NC}"
echo ""

read -p "Do you want to proceed with this configuration? (y/n): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Deployment cancelled."
    exit 1
fi


# ==============================================================================
# 3. EXECUTE DEPLOYMENT
# ==============================================================================

# --- Define derived variables ---
export FUNCTION_SA_EMAIL="${FUNCTION_SA_NAME}@${YOUR_PROJECT_ID}.iam.gserviceaccount.com"
export TRIGGER_SA_EMAIL="${TRIGGER_SA_NAME}@${YOUR_PROJECT_ID}.iam.gserviceaccount.com"

echo "${BOLD}--- Step 1: Creating Service Accounts ---${NC}"
gcloud iam service-accounts create ${FUNCTION_SA_NAME} \
  --display-name="Vertex Search Importer Function SA" \
  --project=${YOUR_PROJECT_ID} || echo "${YELLOW}Warning: Function SA already exists. Skipping creation.${NC}"
gcloud iam service-accounts create ${TRIGGER_SA_NAME} \
  --display-name="Vertex Search Trigger Invoker SA" \
  --project=${YOUR_PROJECT_ID} || echo "${YELLOW}Warning: Trigger SA already exists. Skipping creation.${NC}"

echo "${BOLD}--- Step 2: Granting IAM Permissions ---${NC}"
# Permissions for the FUNCTION SA (to do its job)
echo "  - Granting permissions to the Function SA..."
gcloud projects add-iam-policy-binding ${YOUR_PROJECT_ID} --member="serviceAccount:${FUNCTION_SA_EMAIL}" --role="roles/discoveryengine.admin" --condition=None
gcloud storage buckets add-iam-policy-binding gs://${TRIGGER_BUCKET} --member="serviceAccount:${FUNCTION_SA_EMAIL}" --role="roles/storage.objectViewer" --condition=None

# Permissions for the TRIGGER SA (to manage the event and invoke the function)
echo "  - Granting permissions to the Trigger SA..."
gcloud projects add-iam-policy-binding ${YOUR_PROJECT_ID} --member="serviceAccount:${TRIGGER_SA_EMAIL}" --role="roles/run.invoker" --condition=None
gcloud projects add-iam-policy-binding ${YOUR_PROJECT_ID} --member="serviceAccount:${TRIGGER_SA_EMAIL}" --role="roles/eventarc.eventReceiver" --condition=None

# Permissions for Google-managed Services (to publish the event)
echo "  - Granting permissions to the GCS Service Agent..."
PROJECT_NUMBER=$(gcloud projects describe ${YOUR_PROJECT_ID} --format='value(projectNumber)')
GCS_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding ${YOUR_PROJECT_ID} --member="serviceAccount:${GCS_SERVICE_ACCOUNT}" --role="roles/pubsub.publisher" --condition=None

# Permissions for the Eventarc Service Agent (to validate triggers) ---
echo "  - Granting permissions to the Eventarc Service Agent..."
EVENTARC_SERVICE_ACCOUNT="service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding ${YOUR_PROJECT_ID} --member="serviceAccount:${EVENTARC_SERVICE_ACCOUNT}" --role="roles/eventarc.serviceAgent" --condition=None

echo "${BOLD}--- Step 3: Deploying Cloud Function with dual triggers ---${NC}"
gcloud functions deploy ${FUNCTION_NAME} \
  --gen2 \
  --runtime=python311 \
  --project=${YOUR_PROJECT_ID} \
  --region=${GCP_REGION:-us-central1} \
  --source=. \
  --entry-point=sync_vertex_search \
  --trigger-event=google.cloud.storage.object.v1.finalized \
  --trigger-event=google.cloud.storage.object.v1.deleted \
  --trigger-resource=${TRIGGER_BUCKET} \
  --trigger-location=${TRIGGER_LOCATION} \
  --service-account=${FUNCTION_SA_EMAIL} \
  --trigger-service-account=${TRIGGER_SA_EMAIL} \
  --set-env-vars=PROJECT_ID=${YOUR_PROJECT_ID},LOCATION=${VERTEX_LOCATION:-global},DATA_STORE_ID=${VERTEX_DATA_STORE_ID}

echo ""
echo "${GREEN}${BOLD}=========================================${NC}"
echo "${GREEN}${BOLD} Deployment Complete! ${NC}"
echo "${GREEN}${BOLD}=========================================${NC}"
echo "Your function '${FUNCTION_NAME}' is now active."
echo "It will now sync creations, updates, AND deletions from 'gs://${TRIGGER_BUCKET}'."