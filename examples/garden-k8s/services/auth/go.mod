module github.com/jasoncolburne/better-auth/examples/garden-k8s/auth

go 1.25.1

require (
	github.com/jasoncolburne/better-auth-go v0.0.0-20251020150458-7adc091a9196
	github.com/jasoncolburne/verifiable-storage-go v0.0.0-20251022080739-ed0dd46ef122
	github.com/jmoiron/sqlx v1.4.0
	github.com/lib/pq v1.10.9
	github.com/redis/go-redis/v9 v9.7.0
)

require (
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
	github.com/klauspost/cpuid/v2 v2.0.12 // indirect
	github.com/zeebo/blake3 v0.2.4 // indirect
)

// Use local implementation instead of published version
replace github.com/jasoncolburne/better-auth-go => ../dependencies/better-auth-go
