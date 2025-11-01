package implementation

import (
	"context"
	"fmt"
	"time"
)

// retryRedisOperation executes a Redis operation with retry logic and exponential backoff.
// This ensures graceful recovery when Redis restarts or connections drop.
func retryRedisOperation[T any](ctx context.Context, operation func() (T, error)) (T, error) {
	const maxRetries = 3
	const initialBackoff = 100 * time.Millisecond

	var lastErr error
	var zero T

	for attempt := 0; attempt < maxRetries; attempt++ {
		if attempt > 0 {
			// Exponential backoff: 100ms, 200ms, 400ms
			backoff := initialBackoff * time.Duration(1<<uint(attempt-1))
			time.Sleep(backoff)
		}

		result, err := operation()
		if err != nil {
			lastErr = err
			continue // Retry
		}

		return result, nil
	}

	return zero, fmt.Errorf("redis operation failed after %d retries: %w", maxRetries, lastErr)
}
