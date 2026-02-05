locals {
  # Keycloak clients are no longer managed via Terraform; scripts handle lifecycle.
  manage_keycloak_clients_effective = false
  keycloak_managed_clients          = tomap({})
}
