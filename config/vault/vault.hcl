ui = true

storage "file" {
  path = "/vault/file"
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"
disable_mlock = true

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

log_level = "info"
log_format = "json"