package observability

import (
	"context"
	"log"
	"os"
	"syscall"
	"time"

	otelruntime "go.opentelemetry.io/contrib/instrumentation/runtime"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func Init(ctx context.Context, defaultServiceName string) (func(context.Context) error, error) {
	if os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" {
		return func(context.Context) error { return nil }, nil
	}

	serviceName := os.Getenv("OTEL_SERVICE_NAME")
	if serviceName == "" {
		serviceName = defaultServiceName
	}

	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(serviceName),
			attribute.String("service.namespace", "url-shortener"),
		),
	)
	if err != nil {
		return nil, err
	}

	exporter, err := otlpmetrichttp.New(ctx)
	if err != nil {
		return nil, err
	}

	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(exporter)),
		sdkmetric.WithResource(res),
	)
	otel.SetMeterProvider(mp)
	if err := otelruntime.Start(
		otelruntime.WithMeterProvider(mp),
		otelruntime.WithMinimumReadMemStatsInterval(5*time.Second),
	); err != nil {
		return nil, err
	}
	cpuRegistration, err := registerProcessCPU(mp)
	if err != nil {
		return nil, err
	}
	log.Printf("OpenTelemetry metrics enabled for service %q", serviceName)

	return func(ctx context.Context) error {
		if cpuRegistration != nil {
			if err := cpuRegistration.Unregister(); err != nil {
				log.Printf("OpenTelemetry CPU metric unregister failed: %v", err)
			}
		}
		return mp.Shutdown(ctx)
	}, nil
}

func Shutdown(ctx context.Context, shutdown func(context.Context) error) {
	shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := shutdown(shutdownCtx); err != nil {
		log.Printf("OpenTelemetry shutdown failed: %v", err)
	}
}

func registerProcessCPU(mp *sdkmetric.MeterProvider) (metric.Registration, error) {
	meter := mp.Meter("scale-eng/internal/observability")
	cpu, err := meter.Float64ObservableCounter(
		"process.cpu.seconds",
		metric.WithUnit("s"),
		metric.WithDescription("Total user and system CPU time used by the process."),
	)
	if err != nil {
		return nil, err
	}

	return meter.RegisterCallback(func(ctx context.Context, observer metric.Observer) error {
		observer.ObserveFloat64(cpu, processCPUSeconds())
		return nil
	}, cpu)
}

func processCPUSeconds() float64 {
	var usage syscall.Rusage
	if err := syscall.Getrusage(syscall.RUSAGE_SELF, &usage); err != nil {
		return 0
	}
	return timevalSeconds(usage.Utime) + timevalSeconds(usage.Stime)
}

func timevalSeconds(tv syscall.Timeval) float64 {
	return float64(tv.Sec) + float64(tv.Usec)/1_000_000
}
