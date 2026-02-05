terraform {
  required_providers {
    keycloak = {
      source                = "mrparkers/keycloak"
      configuration_aliases = [keycloak.management]
    }
  }
}

variable "keycloak_base_url" {
  description = "Base URL for the Keycloak admin endpoint"
  type        = string
}

variable "default_realm" {
  description = "Realm to manage"
  type        = string
}

variable "admin_username" {
  description = "Admin username used for management API calls"
  type        = string
}

variable "admin_password" {
  description = "Admin password used for management API calls"
  type        = string
  sensitive   = true
}

variable "client_definitions" {
  description = "Keycloak clients to manage, keyed by client_id"
  type = map(object({
    redirect_uris = list(string)
    web_origins   = list(string)
    root_url      = string
    display_name  = string
  }))
}

data "keycloak_realm" "management" {
  realm    = var.default_realm
  provider = keycloak.management
}

resource "keycloak_openid_client" "managed" {
  provider = keycloak.management
  for_each = nonsensitive(var.client_definitions)

  realm_id  = data.keycloak_realm.management.id
  client_id = each.key
  name      = each.value.display_name

  enabled                      = true
  access_type                  = "CONFIDENTIAL"
  standard_flow_enabled        = true
  direct_access_grants_enabled = false
  service_accounts_enabled     = false
  valid_redirect_uris          = each.value.redirect_uris
  web_origins                  = each.value.web_origins
  root_url                     = each.value.root_url
  base_url                     = each.value.root_url
}

locals {
  managed_clients = tomap({
    for name, client in keycloak_openid_client.managed :
    name => {
      client_id     = client.client_id
      client_secret = client.client_secret
    }
  })
}

output "managed_clients" {
  description = "Client IDs and secrets for managed Keycloak clients"
  value       = local.managed_clients
}
