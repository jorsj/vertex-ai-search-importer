# Vertex AI Search Importer

This project contains a Google Cloud Function that automatically imports files from a Google Cloud Storage (GCS) bucket into a Vertex AI Search data store. The function is triggered whenever a new file is uploaded to the specified GCS bucket.

## Features

-   **Automatic Import:** Automatically imports new files from a GCS bucket to a Vertex AI Search data store.
-   **Supported File Types:** Supports a variety of file types, including `.html`, `.pdf`, `.docx`, `.pptx`, `.txt`, and `.xlsx`.
-   **Easy Deployment:** Includes an interactive deployment script that simplifies the process of setting up the Cloud Function and all necessary permissions.
-   **Secure:** Follows security best practices by creating separate, minimally-privileged service accounts for the function and its trigger.

## Prerequisites

Before you begin, ensure you have the following installed:

-   [Google Cloud SDK](https://cloud.google.com/sdk/install)

You will also need:

-   A Google Cloud Platform project.
-   A GCS bucket.
-   A Vertex AI Search Data Store ID.

## Installation & Deployment

1.  **Clone the repository:**

    ```bash
    git clone https://github.com/your-username/vertex-ai-search-importer.git
    cd vertex-ai-search-importer
    ```

2.  **Run the deployment script:**

    The interactive deployment script will guide you through the process of deploying the Cloud Function.

    ```bash
    ./deploy.sh
    ```

    The script will prompt you for the following information:

    -   **Google Cloud Project ID:** Your Google Cloud project ID.
    -   **GCS bucket name:** The name of the GCS bucket that will trigger the Cloud Function.
    -   **GCP region for the Cloud Function:** The region where you want to deploy the Cloud Function (e.g., `us-central1`).
    -   **Location of your Vertex AI data store:** The location of your Vertex AI data store (e.g., `global`, `us`).
    -   **Vertex AI Search Data Store ID:** The ID of your Vertex AI Search data store.

    The script will then create the necessary service accounts, grant them the required IAM permissions, and deploy the Cloud Function.

## Configuration

The Cloud Function is configured using the following environment variables:

-   `PROJECT_ID`: Your Google Cloud project ID.
-   `LOCATION`: The location of your Vertex AI data store (e.g., `global` or `us`).
-   `DATA_STORE_ID`: Your Vertex AI Search Data Store ID.

These environment variables are automatically set by the `deploy.sh` script during deployment.

## Usage

Once the Cloud Function is deployed, you can trigger it by uploading a supported file to the GCS bucket that you specified during deployment. The function will then automatically import the file into your Vertex AI Search data store.

## Supported File Types

The following file types are supported:

-   `.html`
-   `.pdf`
-   `.docx`
-   `.pptx`
-   `.txt`
-   `.xlsx`

## Dependencies

The project's dependencies are listed in the `requirements.txt` file:

-   `functions-framework==3.*`
-   `google-cloud-discoveryengine==0.9.0`

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.
