.PHONY: deploy

# Configuration variables for deployment. Can be edited for desired behavior.

# Base terraform directory
export tf_dir ?= deploy
# Location for deployed resources
export TF_VAR_REGION ?= europe-central2
# Project id for deployed resources
export TF_VAR_PROJECT_ID ?= project-a-415508
# Artifact Repository name for pushing the Docker images
export TF_VAR_REPO_NAME ?= deploy-demo
# Pushed image name
export TF_VAR_IMAGE_NAME ?= deploy-demo
# Path to the service account credentials
export google_sa_creds ?= key/-service_account.json
# Cloud Storage bucket name
export TF_VAR_BUCKET_NAME ?= deploy-demo_tfstate
# Specifies where to deploy the project. Possible values: `hetzner`, `gce`, `aws`
export CSP ?= hetzner

# Helper variables for deployment.

# Helper var for tagging local image
export tag ?= $(TF_VAR_REGION)-docker.pkg.dev/$(TF_VAR_PROJECT_ID)/$(TF_VAR_REPO_NAME)/$(TF_VAR_IMAGE_NAME)
# Zone location for the resource
export TF_VAR_ZONE ?= $(TF_VAR_REGION)-a
# Hetzner Cloud auth token
export TF_VAR_HCLOUD_TOKEN ?= $(SECRET_CSP_HETZNER)
# AWS Access key for deploying to an EC2 instance
export AWS_ACCESS_KEY_ID ?= $(SECRET_AWS_ACCESS_KEY_ID)
# AWS Secret Access key for deploying to an EC2 instance
export AWS_SECRET_ACCESS_KEY ?= $(SECRET_AWS_ACCESS_KEY)

# Check Hetzner and deployment related keys 
check-hetzner-keys:
	@[ ! -z "${SECRET_CSP_HETZNER}" ] \
    || { echo "ERROR: Key SECRET_CSP_HETZNER does not exist"; exit 1; }

# Check AWS and deployment related keys 
check-aws-keys:
	@[ ! -z "${SECRET_AWS_ACCESS_KEY_ID}" ] \
    || echo "ERROR: Key SECRET_AWS_ACCESS_KEY_ID does not exist"
	@[ ! -z "${SECRET_AWS_ACCESS_KEY}" ] \
    || echo "ERROR: Key SECRET_AWS_ACCESS_KEY does not exist"
	@[ ! -z "${SECRET_AWS_ACCESS_KEY_ID}" ] || exit 1
	@[ ! -z "${SECRET_AWS_ACCESS_KEY}" ] || exit 1

check-gce-keys:
	@echo "All required GCE keys are the same as GCP keys" 

# Check if required GCP keys are present
check-gcp-keys:
	@[ -f key/-service_account.json ] \
    || echo "ERROR: Key file key/-service_account.json does not exist"
	@[ ! -z "${SECRET_STATE_ARCHIVE_KEY}" ] \
    || echo "ERROR: Key SECRET_STATE_ARCHIVE_KEY does not exist"
	@[ -f key/-service_account.json ] || exit 1
	@[ ! -z "${SECRET_STATE_ARCHIVE_KEY}" ] || exit 1

# Start local docker container
start:
	docker compose up -d

# Stop local docker container
stop:
	docker compose down

# Remove created docker image
clean: stop
	docker rmi $(TF_VAR_IMAGE_NAME)
	docker buildx prune -af

# Install gcloud for Debian/Ubuntu
install-gcloud:
	# GCloud
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates gnupg curl sudo
	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
	echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
	sudo apt-get update && sudo apt-get install -y google-cloud-cli

# Install terraform for Debian/Ubuntu
install-terraform:
	sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
	wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
	gpg --no-default-keyring --keyring /usr/share/keyrings/hashicorp-archive-keyring.gpg --fingerprint
	echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
	sudo apt update && sudo apt-get install terraform

# Install gcloud and terraform
install: install-gcloud install-terraform
	gcloud --version
	terraform -version

# Login to GCP with user account
gcp-auth:
	gcloud auth application-default login

# Authorize to GCP with service account
gcp-service:
	gcloud auth activate-service-account --key-file=$(google_sa_creds)

# Add docker repo auth helper
gcp-docker:
	gcloud auth configure-docker $(TF_VAR_REGION)-docker.pkg.dev --quiet

# Initializes all terraform projects
# Downloads required modules and validates .tf files
tf-init:
	terraform -chdir=$(tf_dir)/gar init
	terraform -chdir=$(tf_dir)/gce init
	terraform -chdir=$(tf_dir)/hetzner init
	terraform -chdir=$(tf_dir)/aws init

# Creates Artifact Registry repository on GCP in specified location
create-artifact-repo: tf-init
	terraform -chdir=$(tf_dir)/gar apply -auto-approve

# Builds uarust_conf_site image
build-image:
	docker build . -t name:$(TF_VAR_IMAGE_NAME) -t $(tag)
	docker build . -f Dockerfile.web -t name:$(TF_VAR_IMAGE_NAME) -t $(tag)_2

# Builds and pushes local docker image to the private repository
push-image: gcp-docker create-artifact-repo
	docker push $(tag)
	docker push $(tag)_2

# Creates GCE instance with the website configured on boot
create-gce: check-gce-keys gcp-service state_storage_pull push-image
	terraform -chdir=$(tf_dir)/gce apply -auto-approve

# Creates AWS EC2 instance with the website configured on boot
create-aws: check-aws-keys gcp-service state_storage_pull push-image
	terraform -chdir=$(tf_dir)/aws apply -auto-approve

# Creates Hetzner instance with the website configured on boot
create-hetzner: check-hetzner-keys gcp-service state_storage_pull push-image
	terraform -chdir=$(tf_dir)/hetzner apply -auto-approve

# Deploys everything and updates terraform states
deploy-in-container: create-$(CSP) state_storage_push

# Deploys using tools from the container
deploy: check-gcp-keys build-image
	docker build . -t deploy-$(TF_VAR_IMAGE_NAME) -f ./$(tf_dir)/Dockerfile --build-arg google_sa_creds="$(google_sa_creds)"
	@docker run -v //var/run/docker.sock:/var/run/docker.sock -v .:/app \
    -e SECRET_STATE_ARCHIVE_KEY=$(SECRET_STATE_ARCHIVE_KEY) \
    -e SECRET_CSP_HETZNER=$(SECRET_CSP_HETZNER) \
    -e SECRET_AWS_ACCESS_KEY_ID=$(SECRET_AWS_ACCESS_KEY_ID) \
    -e SECRET_AWS_ACCESS_KEY=$(SECRET_AWS_ACCESS_KEY) \
    -e CSP=$(CSP) \
    --rm deploy-$(TF_VAR_IMAGE_NAME)

# Review changes that terraform will do on apply
tf-plan: tf-init
	terraform -chdir=$(tf_dir)/gar plan
	terraform -chdir=$(tf_dir)/gce plan
	terraform -chdir=$(tf_dir)/hetzner plan
	terraform -chdir=$(tf_dir)/aws plan

# Destroy created infrastracture on GCP
tf-destroy: tf-init
	terraform -chdir=$(tf_dir)/gar destroy
	terraform -chdir=$(tf_dir)/gce destroy
	terraform -chdir=$(tf_dir)/hetzner destroy
	terraform -chdir=$(tf_dir)/aws destroy

# Pushes encrypted terraform state files to the GCS Bucket
state_storage_push:
	@echo Pushing encrypted terraform state files to the GCS Bucket
	-@gcloud storage cp $(tf_dir)/gce/terraform.tfstate gs://$(TF_VAR_BUCKET_NAME)/gce.tfstate --encryption-key="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp $(tf_dir)/gar/terraform.tfstate gs://$(TF_VAR_BUCKET_NAME)/gar.tfstate --encryption-key="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp $(tf_dir)/hetzner/terraform.tfstate gs://$(TF_VAR_BUCKET_NAME)/hetzner.tfstate --encryption-key="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp $(tf_dir)/aws/terraform.tfstate gs://$(TF_VAR_BUCKET_NAME)/aws.tfstate --encryption-key="$(SECRET_STATE_ARCHIVE_KEY)"

# Pulls and decrypts terraform state files to the GCS Bucket
state_storage_pull:
	@echo Pulling terraform state files to the GCS Bucket
	-@gcloud storage cp gs://$(TF_VAR_BUCKET_NAME)/gce.tfstate $(tf_dir)/gce/terraform.tfstate --decryption-keys="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp gs://$(TF_VAR_BUCKET_NAME)/gar.tfstate $(tf_dir)/gar/terraform.tfstate --decryption-keys="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp gs://$(TF_VAR_BUCKET_NAME)/hetzner.tfstate $(tf_dir)/hetzner/terraform.tfstate --decryption-keys="$(SECRET_STATE_ARCHIVE_KEY)"
	-@gcloud storage cp gs://$(TF_VAR_BUCKET_NAME)/aws.tfstate $(tf_dir)/aws/terraform.tfstate --decryption-keys="$(SECRET_STATE_ARCHIVE_KEY)"

# Creates GCS Bucket for terraform states
state_storage_init:
	terraform -chdir=$(tf_dir)/gcs init
	terraform -chdir=$(tf_dir)/gcs apply

# Destroys GCS Bucket for terraform states
state_storage_destroy:
	terraform -chdir=$(tf_dir)/gcs destroy
