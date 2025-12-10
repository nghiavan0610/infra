# Application read-only policy
# Apps can only read secrets from their namespace

path "secret/data/{{identity.entity.name}}/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/{{identity.entity.name}}/*" {
  capabilities = ["list"]
}
