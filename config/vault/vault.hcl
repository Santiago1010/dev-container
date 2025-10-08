ui = true

storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address = "0.0.0.0:8200"
  tls_disable = "true"
}

api_addr = "http://0.0.0.0:8200"
cluster_addr = "https://0.0.0.0:8201"
disable_mlock = true

# Habilitar telemetría
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Configuración de logs
log_level = "info"
log_format = "json"