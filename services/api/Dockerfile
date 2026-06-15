FROM golang:1.22-bookworm AS build

WORKDIR /src
COPY go.mod go.sum ./
COPY internal ./internal
COPY services/api ./services/api

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/api ./services/api

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/api /api

EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/api"]
