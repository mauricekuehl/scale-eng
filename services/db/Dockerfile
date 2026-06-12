FROM golang:1.22-bookworm AS build

WORKDIR /src
COPY go.mod ./
COPY services/db ./services/db

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/db ./services/db

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/db /db

EXPOSE 9000
USER nonroot:nonroot
ENTRYPOINT ["/db"]
