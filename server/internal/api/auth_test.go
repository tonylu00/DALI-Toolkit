package api

import (
	"crypto/tls"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestGetCallbackURL(t *testing.T) {
	gin.SetMode(gin.TestMode)
	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	req := httptest.NewRequest("GET", "http://example.com/anything", nil)
	c.Request = req

	h := &AuthHandler{}
	url := h.getCallbackURL(c)
	if url != "http://example.com/api/v1/auth/callback" {
		t.Fatalf("expected http callback url, got %s", url)
	}

	// HTTPS via TLS
	reqTLS := httptest.NewRequest("GET", "https://secure.example.com/anything", nil)
	reqTLS.TLS = &tls.ConnectionState{}
	c.Request = reqTLS
	url = h.getCallbackURL(c)
	if url != "https://secure.example.com/api/v1/auth/callback" {
		t.Fatalf("expected https callback url, got %s", url)
	}

	// HTTPS via header
	req2 := httptest.NewRequest("GET", "http://proxy.example.com/anything", nil)
	req2.Header.Set("X-Forwarded-Proto", "https")
	c.Request = req2
	url = h.getCallbackURL(c)
	if url != "https://proxy.example.com/api/v1/auth/callback" {
		t.Fatalf("expected https callback via header, got %s", url)
	}
}
