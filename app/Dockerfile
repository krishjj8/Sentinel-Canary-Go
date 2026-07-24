FROM golang:1.23-alpine AS builder

WORKDIR /src

ENV GOTOOLCHAIN=auto

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o sentinel .

#Distroless Runtime

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /
COPY --from=builder /src/sentinel /sentinel

USER nonroot:nonroot
EXPOSE 8080

ENTRYPOINT ["/sentinel"]