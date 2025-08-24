package errors

import (
	"net/http"
	"testing"
)

func TestAppError_Error(t *testing.T) {
	err := &AppError{
		Code:    "TEST_ERROR",
		Message: "This is a test error",
	}

	expected := "TEST_ERROR: This is a test error"
	if err.Error() != expected {
		t.Errorf("Expected %s, got %s", expected, err.Error())
	}
}

func TestNewInternalError(t *testing.T) {
	err := NewInternalError("Something went wrong")

	if err.Code != ErrCodeInternal {
		t.Errorf("Expected code %s, got %s", ErrCodeInternal, err.Code)
	}

	if err.HTTPStatus != http.StatusInternalServerError {
		t.Errorf("Expected status %d, got %d", http.StatusInternalServerError, err.HTTPStatus)
	}

	if err.Message != "Something went wrong" {
		t.Errorf("Expected message 'Something went wrong', got %s", err.Message)
	}
}

func TestNewValidationError(t *testing.T) {
	details := map[string]interface{}{
		"field": "name",
		"error": "required",
	}
	err := NewValidationError("Validation failed", details)

	if err.Code != ErrCodeValidation {
		t.Errorf("Expected code %s, got %s", ErrCodeValidation, err.Code)
	}

	if err.HTTPStatus != http.StatusBadRequest {
		t.Errorf("Expected status %d, got %d", http.StatusBadRequest, err.HTTPStatus)
	}

	if err.Details == nil {
		t.Error("Expected details to be set")
	}
}