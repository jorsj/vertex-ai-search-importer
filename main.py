import os
import functions_framework

from google.api_core.exceptions import GoogleAPICallError
from google.cloud import discoveryengine_v1 as discoveryengine

# --- Configuration ---
# Set these as environment variables in your Cloud Function
PROJECT_ID = os.environ.get("PROJECT_ID")
LOCATION = os.environ.get("LOCATION")  # e.g., "global" or "us"
DATA_STORE_ID = os.environ.get("DATA_STORE_ID")

# --- Constants ---
# Define the file extensions that should trigger the import
ALLOWED_EXTENSIONS = {".html", ".pdf", ".docx", ".pptx", ".txt", ".xlsx"}

# Initialize the Vertex AI Search Document Service client
document_service_client = discoveryengine.DocumentServiceClient()


@functions_framework.cloud_event
def update_vertex_search(cloud_event):
    """
    Cloud Function triggered by a new file in a GCS bucket.
    It imports the file into a Vertex AI Search data store if the format is supported.

    Args:
        cloud_event: The CloudEvent object representing the GCS event.
                     The data payload contains 'bucket' and 'name' of the file.
    """
    # Extract file details from the event
    data = cloud_event.data
    bucket_name = data.get("bucket")
    file_name = data.get("name")

    if not all([bucket_name, file_name, PROJECT_ID, LOCATION, DATA_STORE_ID]):
        print("Error: Missing file details or environment variables (PROJECT_ID, LOCATION, DATA_STORE_ID).")
        return

    print(f"Processing file: gs://{bucket_name}/{file_name}")

    # 1. Check if the file extension is in our allowed list
    _, extension = os.path.splitext(file_name)
    if extension.lower() not in ALLOWED_EXTENSIONS:
        print(f"Skipping file '{file_name}' with unsupported extension '{extension}'.")
        return

    # 2. Construct the full GCS URI for the document
    gcs_uri = f"gs://{bucket_name}/{file_name}"

    # 3. Prepare the import request for Vertex AI Search
    # The parent path for the data store branch
    parent = document_service_client.branch_path(
        project=PROJECT_ID,
        location=LOCATION,
        data_store=DATA_STORE_ID,
        branch="default_branch",  # Use 'default_branch' unless you use custom branches
    )

    # Configure the request
    request = discoveryengine.ImportDocumentsRequest(
        parent=parent,
        gcs_source=discoveryengine.GcsSource(input_uris=[gcs_uri], data_schema="content"),
        # INCREMENTAL mode adds new documents and updates existing ones.
        # Use FULL to replace the entire data store with the contents of the GCS path.
        reconciliation_mode=discoveryengine.ImportDocumentsRequest.ReconciliationMode.INCREMENTAL,
    )

    # 4. Start the import operation
    try:
        operation = document_service_client.import_documents(request=request)
        print(f"Started Vertex AI Search import operation: {operation.operation.name}")
        print(f"Successfully triggered import for: {gcs_uri}")

    except GoogleAPICallError as e:
        print(f"Error calling Vertex AI Search API for file {gcs_uri}: {e}")
        # Depending on the error, you might want to raise it to trigger a retry
        raise