# Se evalúa sobre `terraform show -json tfplan` de cada stack.
package dcp.terraform.tags

import rego.v1

mandatory := {
	"Name", "Environment", "Scope", "Owner", "CostCenter", "DataClassification",
	"Compliance", "ManagedBy", "Application", "Repository", "TerraformStack",
}

workload_tags := {"Domain", "Workload"}

catalog := {
	"Environment": {"dev", "qa", "stg", "prod"},
	"Scope": {"diners", "data", "platform", "security", "networking"},
	"DataClassification": {"public", "internal", "confidential", "restricted", "pci"},
	"Compliance": {"general", "pci-dss", "lpdp"},
	"ManagedBy": {"terraform", "control-tower", "aws-managed"},
}

forbidden_values := {"", "unknown", "temp", "shared", "n/a", "na"}

changes contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
	"tags_all" in object.keys(rc.change.after)
}

deny contains msg if {
	some rc in changes
	missing := mandatory - object.keys(rc.change.after.tags_all)
	count(missing) > 0
	msg := sprintf("%s: faltan tags obligatorios %v", [rc.address, missing])
}

deny contains msg if {
	some rc in changes
	contains(rc.change.after.tags_all.TerraformStack, "/workloads/")
	missing := workload_tags - object.keys(rc.change.after.tags_all)
	count(missing) > 0
	msg := sprintf("%s: recurso de workload sin %v", [rc.address, missing])
}

deny contains msg if {
	some rc in changes
	some key, allowed in catalog
	value := rc.change.after.tags_all[key]
	not value in allowed
	msg := sprintf("%s: %s = %q no está en catalogos-cloud.yaml", [rc.address, key, value])
}

deny contains msg if {
	some rc in changes
	some key, value in rc.change.after.tags_all
	lower(value) in forbidden_values
	msg := sprintf("%s: el tag %s no puede valer %q", [rc.address, key, value])
}

deny contains msg if {
	some rc in changes
	name := rc.change.after.tags_all.Name
	not startswith(name, "dcp-")
	not startswith(name, "/dcp/")
	not startswith(name, "/aws/")
	not startswith(name, "alias/dcp/")
	msg := sprintf("%s: Name = %q no sigue el patrón dcp-", [rc.address, name])
}
