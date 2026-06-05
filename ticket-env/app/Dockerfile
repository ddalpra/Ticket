# ── Stage 1: build ────────────────────────────────────────────────────────────
FROM docker.io/golang:1.22-alpine AS builder

RUN apk add --no-cache git ca-certificates tzdata

WORKDIR /build

# Copia go.mod e go.sum prima per sfruttare la cache layer
COPY go.mod go.sum ./
RUN go mod download

# Copia il resto del sorgente
COPY . .

# Genera il codice Ent
RUN go generate ./ent/...

# Build statico
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-w -s" -o ticket-service ./cmd/server

# ── Stage 2: runtime ───────────────────────────────────────────────────────────
FROM docker.io/alpine:3.19

RUN apk add --no-cache ca-certificates tzdata curl

WORKDIR /app

COPY --from=builder /build/ticket-service .

# User non-root per sicurezza (Podman-friendly)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/health || exit 1

ENTRYPOINT ["./ticket-service"]
