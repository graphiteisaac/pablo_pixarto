FROM golang:1.27.2-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

# Build a statically linked binary
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /bot ./cmd/bot

FROM gcr.io/distroless/static-debian12

COPY --from=builder /bot /bot

USER nonroot:nonroot

ENTRYPOINT ["/bot"]
