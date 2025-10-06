storage "consul" {
  address = "consul:8500"
  path    = "vault/"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

service_registration "consul" {
  address = "consul:8500"
  service = "vault"
}

ui = true

log_level = "info"
disable_mlock = true
api_addr = "http://vault:8200"
cluster_addr = "http://vault:8201"
