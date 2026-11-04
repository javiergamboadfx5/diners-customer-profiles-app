# Guardrails para repos de workload: lo que un proyecto nunca crea y lo que siempre cifra.
package dcp.terraform.guardrails

import rego.v1

# Red central: la administra Networking (L13).
network_owned_by_platform := {
	"aws_vpc", "aws_subnet", "aws_internet_gateway", "aws_nat_gateway",
	"aws_ec2_transit_gateway", "aws_ec2_transit_gateway_vpc_attachment",
	"aws_vpc_peering_connection", "aws_route_table", "aws_route",
}

created contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	"create" in rc.change.actions
}

changed contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

deny contains msg if {
	some rc in created
	rc.type in network_owned_by_platform
	msg := sprintf("%s: %s lo administra Networking, no un repo de workload", [rc.address, rc.type])
}

deny contains msg if {
	some rc in changed
	rc.type in {"aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_egress_rule"}
	rc.change.after.cidr_ipv4 == "0.0.0.0/0"
	msg := sprintf("%s: regla con 0.0.0.0/0 prohibida", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_security_group"
	some rule in rc.change.after.ingress
	"0.0.0.0/0" in rule.cidr_blocks
	msg := sprintf("%s: ingreso desde 0.0.0.0/0 prohibido", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_rds_cluster"
	not rc.change.after.storage_encrypted
	msg := sprintf("%s: RDS sin cifrado", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type in {"aws_rds_cluster_instance", "aws_db_instance"}
	rc.change.after.publicly_accessible
	msg := sprintf("%s: base de datos pública", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	some m in rc.change.after.metadata_options
	m.http_tokens != "required"
	msg := sprintf("%s: IMDSv2 obligatorio", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_iam_role"
	not rc.change.after.permissions_boundary
	msg := sprintf("%s: rol sin permission boundary", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_iam_access_key"
	msg := sprintf("%s: access keys prohibidas", [rc.address])
}
