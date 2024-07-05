package main

import (
	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"context"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

var (
	taskQueue string
	targetUrl string

	client *cloudtasks.Client
)

func main() {
	// Get the task queue name from env vars
	taskQueue = os.Getenv("TASK_QUEUE")
	if taskQueue == "" {
		log.Fatal("TASK_QUEUE not set")
	}
	fmt.Printf("use task_queue: %s\n", taskQueue)

	// Get the task target URL from env vars
	targetUrl = os.Getenv("TARGET_URL")
	if targetUrl == "" {
		log.Fatal("TARGET_URL not set")
	}
	fmt.Printf("use target_url: %s\n", targetUrl)

	ctx := context.Background()
	var err error

	// PUblish to Cloud Task
	client, err = cloudtasks.NewClient(ctx)
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", getEvent)
	http.ListenAndServe(":8080", nil)
}

func getEvent(w http.ResponseWriter, r *http.Request) {

	body, err := io.ReadAll(r.Body)
	defer r.Body.Close()
	if err != nil {
		fmt.Printf("Failed to read request body: %v", err)
		return
	}

	taskName := ""
	// format the headers
	headers := make(map[string]string)
	for k, v := range r.Header {
		headers[k] = v[0]
		if k == "Ce-Id" {
			taskName = v[0]
			taskName = strings.ReplaceAll(taskName, ".", "_")
			taskName = strings.ReplaceAll(taskName, "/", "-")
			taskName = strings.ReplaceAll(taskName, "%", "")
		}
	}

	req := &cloudtaskspb.CreateTaskRequest{
		Parent: taskQueue,
		Task: &cloudtaskspb.Task{
			Name: fmt.Sprintf("%s/tasks/%s", taskQueue, taskName),
			MessageType: &cloudtaskspb.Task_HttpRequest{
				HttpRequest: &cloudtaskspb.HttpRequest{
					HttpMethod: cloudtaskspb.HttpMethod_POST,
					Url:        targetUrl,
					Body:       body,
					Headers:    headers,
				},
			},
		},
	}
	ctx := context.Background()
	_, err = client.CreateTask(ctx, req)
	if err != nil {
		fmt.Printf("Failed to create task: %v", err)
		return
	} else {
		fmt.Printf("Task created: %v", req)
		w.WriteHeader(http.StatusOK)
	}
}
