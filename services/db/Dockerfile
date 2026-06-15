FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    OTEL_TRACES_EXPORTER=none \
    OTEL_METRICS_EXPORTER=none \
    OTEL_LOGS_EXPORTER=none

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY services/db/app.py .

EXPOSE 9000

RUN useradd --create-home --shell /usr/sbin/nologin appuser
USER appuser

CMD ["opentelemetry-instrument", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "9000", "--no-access-log"]
