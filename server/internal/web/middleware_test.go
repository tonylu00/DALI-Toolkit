package web

import "testing"

func TestIsStaticAsset(t *testing.T) {
	yes := []string{"/assets/app.js", "/canvaskit/foo.wasm", "/favicon.png", "/styles.css", "/img/logo.svg"}
	for _, p := range yes {
		if !isStaticAsset(p) {
			t.Fatalf("expected static asset for %s", p)
		}
	}
	no := []string{"/api/v1/devices", "/app/index", "/ws"}
	for _, p := range no {
		if isStaticAsset(p) {
			t.Fatalf("did not expect static asset for %s", p)
		}
	}
}

func TestIsWebAppRequest(t *testing.T) {
	if !isWebAppRequest("/app/") {
		t.Fatal("expected /app/ to be web app request")
	}
	if isWebAppRequest("/api/v1/auth/me") {
		t.Fatal("expected /api path not to be web app request")
	}
}
