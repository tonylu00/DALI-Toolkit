package web

import (
	"embed"
	"io/fs"
	"net/http"
)

//go:embed flutter_web/*
var flutterWebFS embed.FS

// GetFlutterWebFS returns the embedded Flutter web filesystem
func GetFlutterWebFS() (fs.FS, error) {
	return fs.Sub(flutterWebFS, "flutter_web")
}

// GetFlutterWebHandler returns an HTTP handler for the embedded Flutter web app
func GetFlutterWebHandler() (http.Handler, error) {
	webFS, err := GetFlutterWebFS()
	if err != nil {
		return nil, err
	}
	return http.FileServer(http.FS(webFS)), nil
}
