## Grafana Walkthrough (Slide Guide)

- **Objective**: Monitor Snake Game SLOs: availability 99.5%, p99 latency < 500 ms, error rate < 1%.

- **Dashboard: Snake Game Overview**
  - HTTP Requests Rate: `sum(rate(snake_http_requests_total[5m]))` — traffic trend.
  - Active Sessions: `snake_active_sessions` — concurrent gameplay.
  - Scores Submitted: `rate(snake_scores_submitted_total[5m])` — engagement.
  - Ingress Request Rate: `sum(rate(nginx_ingress_controller_requests[5m]))` — edge throughput.
  - Ingress Latencies (p50/p90/p99): histogram_quantile over `nginx_ingress_controller_request_duration_seconds_bucket` — user perf.
  - App CPU: `sum(rate(container_cpu_usage_seconds_total{pod=~"snake-game-.*"}[5m]))` — scaling signal.
  - Restarts: `increase(kube_pod_container_status_restarts_total{namespace="snake"}[1h])` — stability.

- **Alerts (examples)**
  - High error rate 5m > 2%: `sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m])) / sum(rate(nginx_ingress_controller_requests[5m])) > 0.02`
  - High latency p99 > 0.5s: `histogram_quantile(0.99, sum(rate(nginx_ingress_controller_request_duration_seconds_bucket[5m])) by (le)) > 0.5`
  - CPU > 80% 10m: `sum(rate(container_cpu_usage_seconds_total{pod=~"snake-game-.*"}[10m])) / sum(kube_pod_container_resource_limits{resource="cpu", namespace="snake"}) > 0.8`

- **How to access**
  - Grafana Service Type: LoadBalancer (admin/admin123) — change password in values.
  - Import dashboard JSON at `grafana/dashboards/snake-game.json` or mount via ConfigMap.


