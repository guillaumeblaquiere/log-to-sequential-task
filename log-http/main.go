package main

import (
	"fmt"
	"io"
	"net/http"
	"strings"
)

func main() {
	http.HandleFunc("/", logRequest)
	http.ListenAndServe(":8080", nil)
}

func logRequest(w http.ResponseWriter, r *http.Request) {
	logString := "The request content is:\n"

	logString += fmt.Sprintf("Requested URL: \t\t%s\n", r.URL)

	logString += fmt.Sprintf("Requested Method: \t%s\n", r.Method)
	logString += fmt.Sprintf("Remote address: \t%s\n", r.RemoteAddr)
	logString += fmt.Sprintf("Requested user agent: \t%s\n", r.UserAgent())

	logString += fmt.Sprintf("Headers are: \n")
	for h, v := range r.Header {
		logString += fmt.Sprintf("\t %s: %s\n", h, strings.Join(v, ","))
	}

	defer r.Body.Close()
	content, _ := io.ReadAll(r.Body)
	logString += fmt.Sprintf("Body Content: \n%s\n", string(content))

	fmt.Println(logString)
	fmt.Fprintf(w, "%s", logString)
}
