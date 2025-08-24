package errors

import (
	"fmt"
	"net/http"
)

// AppError represents an application error
type AppError struct {
	Code       string                 `json:"code"`
	Message    string                 `json:"message"`
	Details    map[string]interface{} `json:"details,omitempty"`
	HTTPStatus int                    `json:"-"`
}

func (e *AppError) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// Common error codes
const (
	ErrCodeInternal     = "INTERNAL_ERROR"
	ErrCodeValidation   = "VALIDATION_ERROR"
	ErrCodeNotFound     = "NOT_FOUND"
	ErrCodeUnauthorized = "UNAUTHORIZED"
	ErrCodeForbidden    = "FORBIDDEN"
	ErrCodeConflict     = "CONFLICT"
	ErrCodeBadRequest   = "BAD_REQUEST"
)

// Helper functions for common errors
func NewInternalError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeInternal,
		Message:    message,
		HTTPStatus: http.StatusInternalServerError,
	}
}

func NewValidationError(message string, details map[string]interface{}) *AppError {
	return &AppError{
		Code:       ErrCodeValidation,
		Message:    message,
		Details:    details,
		HTTPStatus: http.StatusBadRequest,
	}
}

func NewNotFoundError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeNotFound,
		Message:    message,
		HTTPStatus: http.StatusNotFound,
	}
}

func NewUnauthorizedError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeUnauthorized,
		Message:    message,
		HTTPStatus: http.StatusUnauthorized,
	}
}

func NewForbiddenError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeForbidden,
		Message:    message,
		HTTPStatus: http.StatusForbidden,
	}
}

func NewConflictError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeConflict,
		Message:    message,
		HTTPStatus: http.StatusConflict,
	}
}

func NewBadRequestError(message string) *AppError {
	return &AppError{
		Code:       ErrCodeBadRequest,
		Message:    message,
		HTTPStatus: http.StatusBadRequest,
	}
}
