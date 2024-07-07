#####################################################################
####                     COMMON RESOURCES                        ####
#####################################################################

# Create a service account to create task
gcloud iam service-accounts create create-task-service-account --display-name "Create Task Service Account"

# Cloud run service which log the HTTP request
gcloud run deploy log-http --source=log-http/. --region=us-central1 --allow-unauthenticated

#####################################################################
####                 Cloud logging sink option                   ####
#####################################################################

# Create a Cloud task with URL override
gcloud tasks queues create sequential-task-override \
  --http-uri-override=host:$(gcloud run services describe log-http --region=us-central1 --format='value(status.url)' | sed 's,http[s]*://,,g') \
  --location=us-central1 --max-concurrent-dispatches=1

# Create a topic
gcloud pubsub topics create log-topic

#Grant the service account the cloud task creation permission
gcloud tasks queues add-iam-policy-binding sequential-task-override \
  --location=us-central1 \
  --role=roles/cloudtasks.enqueuer \
  --member="serviceAccount:$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)')"


# create a subscription
gcloud pubsub subscriptions create log-subscription \
  --topic=log-topic \
  --push-endpoint="https://cloudtasks.googleapis.com/v2/$(gcloud tasks queues describe sequential-task-override --location=us-central1 --format='value(name)')/tasks:buffer" \
  --push-auth-service-account=$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)') \
  --push-no-wrapper

# Create log sink to the topic
gcloud logging sinks create log-sink \
  pubsub.googleapis.com/projects/$(gcloud config get-value project)/topics/log-topic \
  --log-filter='protoPayload.methodName="jobservice.jobcompleted"'

# Add permission to publish events into PubSub
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="$(gcloud logging sinks describe log-sink --format='value(writerIdentity)')" \
  --role=roles/pubsub.publisher


#####################################################################
####                      Eventarc option                        ####
#####################################################################

# Create a Cloud task
gcloud tasks queues create sequential-task \
  --location=us-central1 --max-concurrent-dispatches=1

#Grant the service account the cloud task creation permission
gcloud tasks queues add-iam-policy-binding sequential-task \
  --location=us-central1 \
  --role=roles/cloudtasks.enqueuer \
  --member="serviceAccount:$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)')"

# Deploy event-to-task cloud run service
gcloud run deploy event-to-task --source=event-to-task/. --region=us-central1 \
  --allow-unauthenticated \
  --set-env-vars=TASK_QUEUE="$(gcloud tasks queues describe sequential-task --location=us-central1 --format='value(name)')",TARGET_URL="$(gcloud run services describe log-http --region=us-central1 --format='value(status.url)')" \
  --service-account=$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)')

# Create a service account to receive events
gcloud iam service-accounts create eventarc-service-account --display-name "Eventarc Service Account"

# Add permission to receive events
gcloud projects add-iam-policy-binding $(gcloud config get-value project) \
  --member="serviceAccount:$(gcloud iam service-accounts list --filter="displayName='Eventarc Service Account'" --format='value(email)')" \
  --role=roles/eventarc.eventReceiver


# Deploy eventarc on audit log protoPayload.methodName='jobservice.jobcompleted' to invoke the event-to-task cloud run service
gcloud eventarc triggers create event-to-task-trigger \
  --location=us-central1 \
  --event-filters="type=google.cloud.audit.log.v1.written" \
  --event-filters='methodName=jobservice.jobcompleted' \
  --event-filters='serviceName=bigquery.googleapis.com' \
  --destination-run-service=event-to-task \
  --destination-run-region=us-central1 \
  --service-account="$(gcloud iam service-accounts list --filter="displayName='Eventarc Service Account'" --format='value(email)')"

#####################################################################
####                        Hack option                          ####
#####################################################################

# Deploy eventarc on audit log protoPayload.methodName='jobservice.jobcompleted' to invoke the event-to-task cloud run service
gcloud eventarc triggers create event-to-task-trigger-hack \
  --location=us-central1 \
  --event-filters="type=google.cloud.audit.log.v1.written" \
  --event-filters='methodName=jobservice.jobcompleted' \
  --event-filters='serviceName=bigquery.googleapis.com' \
  --destination-run-service=event-to-task \
  --destination-run-region=us-central1 \
  --service-account="$(gcloud iam service-accounts list --filter="displayName='Eventarc Service Account'" --format='value(email)')"

# Create a Cloud task with URL override
gcloud tasks queues create sequential-task-override-hack \
  --http-uri-override=host:$(gcloud run services describe log-http --region=us-central1 --format='value(status.url)' | sed 's,http[s]*://,,g') \
  --location=us-central1 --max-concurrent-dispatches=1

#Grant the service account the cloud task creation permission
gcloud tasks queues add-iam-policy-binding sequential-task-override-hack \
  --location=us-central1 \
  --role=roles/cloudtasks.enqueuer \
  --member="serviceAccount:$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)')"

# Update the eventarc automatically created subscription to use a different service account and endpoint
gcloud pubsub subscriptions update \
 "$(gcloud pubsub subscriptions list --format='value(name)' | grep "event-to-task-trigger-hack")" \
 --push-endpoint="https://cloudtasks.googleapis.com/v2/$(gcloud tasks queues describe sequential-task-override-hack --location=us-central1 --format='value(name)')/tasks:buffer" \
 --push-auth-service-account=$(gcloud iam service-accounts list --filter="displayName='Create Task Service Account'" --format='value(email)') \
 --push-auth-token-audience="" \
 --push-no-wrapper

#####################################################################
####                       Simulate event                        ####
#####################################################################

# Generate BigQuery audit log
bq query "select 1"