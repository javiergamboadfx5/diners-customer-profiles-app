# Guardrails para los stacks de Amazon Connect (contactcenter-<env>).
# Se evalúa sobre `terraform show -json tfplan` de cada stack.
# Feature: connect-instance-initial-build
# Cubre: KMS, S3, recursos protegidos, Customer Profiles y federación SAML.
package dcp.terraform.connect

import rego.v1

# ---------------------------------------------------------------------------
# Helpers comunes sobre el plan JSON
# ---------------------------------------------------------------------------

# Cambios gestionados que crean o actualizan un recurso.
changed contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update"}
}

# Cambios gestionados que crean, actualizan o reemplazan un recurso.
# Terraform expresa un reemplazo como la pareja de acciones ["delete","create"]
# (o ["create","delete"]); por eso se evalúa la lista completa de acciones.
touched contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	some action in rc.change.actions
	action in {"create", "update", "delete"}
}

# Acciones de borrado, incluido el borrado dentro de un reemplazo.
is_delete(rc) if "delete" in rc.change.actions

# Tipos de recurso que representan un dominio de Customer Profiles,
# ya sea con el provider aws o awscc (OQ-12).
profiles_domain_types := {"aws_customerprofiles_domain", "awscc_customerprofiles_domain"}

# Tipos de recurso que representan un object type de Customer Profiles.
profiles_object_type_types := {"aws_customerprofiles_object_type", "awscc_customerprofiles_object_type"}

# Recursos protegidos por prevent_destroy. Un plan nunca debe borrarlos ni
# reemplazarlos (Property 13).
protected_types := {"aws_kms_key", "aws_s3_bucket", "aws_connect_instance"} | profiles_domain_types

# Devuelve la política KMS de un recurso como objeto, parseando el JSON
# cuando viene como cadena (que es lo habitual en el plan).
kms_policy(rc) := policy if {
	raw := rc.change.after.policy
	is_string(raw)
	policy := json.unmarshal(raw)
}

kms_policy(rc) := policy if {
	policy := rc.change.after.policy
	is_object(policy)
}

# Normaliza Statement a una lista de statements.
statements(policy) := policy.Statement if {
	is_array(policy.Statement)
}

statements(policy) := [policy.Statement] if {
	is_object(policy.Statement)
}

# Lista de acciones de un statement, siempre como array.
stmt_actions(stmt) := stmt.Action if is_array(stmt.Action)

stmt_actions(stmt) := [stmt.Action] if is_string(stmt.Action)

# Acciones KMS que manipulan datos (cifrado/descifrado). Prohibidas en el
# statement de administración de la llave (Req 4.2, 7.2).
kms_data_action_prefixes := {"kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:ReEncrypt"}

has_data_action(stmt) if {
	some action in stmt_actions(stmt)
	some prefix in kms_data_action_prefixes
	startswith(action, prefix)
}

# Un statement de administración es el que puede borrar/programar borrado de la
# llave sin ser un rol de servicio. Se identifica por ScheduleKeyDeletion.
is_admin_statement(stmt) if {
	some action in stmt_actions(stmt)
	action == "kms:ScheduleKeyDeletion"
}

# Un principal es de servicio AWS cuando lleva la clave Service.
service_principal(stmt) if _ := stmt.Principal.Service

# Detecta Principal: "*" (en cualquiera de sus formas) sin Condition.
wildcard_principal(stmt) if stmt.Principal == "*"

wildcard_principal(stmt) if stmt.Principal.AWS == "*"

wildcard_principal(stmt) if {
	some p in stmt.Principal.AWS
	p == "*"
}

has_condition(stmt) if count(object.keys(stmt.Condition)) > 0

# ---------------------------------------------------------------------------
# KMS (Req 4.3, 7.5, 7.9 — rotación, admin sin datos, SourceAccount, wildcard)
# ---------------------------------------------------------------------------

# Rotación obligatoria en toda CMK.
deny contains msg if {
	some rc in changed
	rc.type == "aws_kms_key"
	rc.change.after.enable_key_rotation != true
	msg := sprintf("%s: la CMK debe tener enable_key_rotation = true", [rc.address])
}

# El statement de administración de la llave no puede llevar acciones de datos.
deny contains msg if {
	some rc in changed
	rc.type == "aws_kms_key"
	policy := kms_policy(rc)
	some stmt in statements(policy)
	is_admin_statement(stmt)
	has_data_action(stmt)
	msg := sprintf("%s: el statement de administración de la CMK no puede incluir acciones de datos (Encrypt/Decrypt/GenerateDataKey/ReEncrypt)", [rc.address])
}

# Todo statement con principal de servicio debe condicionarse con aws:SourceAccount.
deny contains msg if {
	some rc in changed
	rc.type == "aws_kms_key"
	policy := kms_policy(rc)
	some stmt in statements(policy)
	service_principal(stmt)
	not stmt.Condition.StringEquals["aws:SourceAccount"]
	msg := sprintf("%s: el statement de la CMK para un principal de servicio debe condicionar aws:SourceAccount", [rc.address])
}

# Ningún Allow con Principal: "*" sin Condition.
deny contains msg if {
	some rc in changed
	rc.type == "aws_kms_key"
	policy := kms_policy(rc)
	some stmt in statements(policy)
	stmt.Effect == "Allow"
	wildcard_principal(stmt)
	not has_condition(stmt)
	msg := sprintf("%s: la política de la CMK no puede tener un Allow con Principal \"*\" sin Condition", [rc.address])
}

# ---------------------------------------------------------------------------
# S3 (Req 5.2, 5.4, 5.8 — BPA, ownership, cifrado aws:kms, SecureTransport)
# ---------------------------------------------------------------------------

# Block Public Access: las cuatro opciones en true.
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_public_access_block"
	some setting in [
		"block_public_acls",
		"block_public_policy",
		"ignore_public_acls",
		"restrict_public_buckets",
	]
	rc.change.after[setting] != true
	msg := sprintf("%s: %s debe ser true (Block Public Access)", [rc.address, setting])
}

# Ownership controls: BucketOwnerEnforced.
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_ownership_controls"
	some rule in rc.change.after.rule
	rule.object_ownership != "BucketOwnerEnforced"
	msg := sprintf("%s: object_ownership debe ser BucketOwnerEnforced", [rc.address])
}

# Cifrado por defecto con SSE-KMS (aws:kms), nunca AES256 ni sin cifrado.
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_server_side_encryption_configuration"
	some rule in rc.change.after.rule
	some apply in rule.apply_server_side_encryption_by_default
	apply.sse_algorithm != "aws:kms"
	msg := sprintf("%s: el cifrado por defecto del bucket debe ser aws:kms, no %q", [rc.address, apply.sse_algorithm])
}

# La política del bucket debe negar el transporte inseguro (SecureTransport=false).
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_policy"
	policy := json.unmarshal(rc.change.after.policy)
	not has_secure_transport_deny(policy)
	msg := sprintf("%s: la política del bucket debe negar aws:SecureTransport = false", [rc.address])
}

has_secure_transport_deny(policy) if {
	some stmt in statements(policy)
	stmt.Effect == "Deny"
	stmt.Condition.Bool["aws:SecureTransport"] == "false"
}

has_secure_transport_deny(policy) if {
	some stmt in statements(policy)
	stmt.Effect == "Deny"
	stmt.Condition.Bool["aws:SecureTransport"] == false
}

# ---------------------------------------------------------------------------
# Recursos protegidos (Req 4.5, 5.8, 6.6, 7.9, 8.8 — Property 13)
# ---------------------------------------------------------------------------

# Nunca borrar ni reemplazar una CMK, un bucket, la instancia Connect ni el
# dominio de Customer Profiles. El reemplazo se detecta por la acción delete.
deny contains msg if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.type in protected_types
	is_delete(rc)
	msg := sprintf("%s: recurso protegido (%s) no puede borrarse ni reemplazarse; acciones=%v", [rc.address, rc.type, rc.change.actions])
}

# ---------------------------------------------------------------------------
# Customer Profiles (Req 8.10, 11.3 — campos PAN/SAD prohibidos, tags)
# ---------------------------------------------------------------------------

# Nombres de campo que no pueden aparecer en un object type (PAN/SAD).
# La comparación es laxa: cualquier nombre que contenga uno de estos tokens.
forbidden_field_tokens := {
	"pan",
	"primaryaccountnumber",
	"cardnumber",
	"creditcard",
	"debitcard",
	"accountnumber",
	"cvv",
	"cvv2",
	"cvc",
	"cvc2",
	"cid",
	"cav2",
	"pin",
	"pinblock",
	"track",
	"track1",
	"track2",
	"magstripe",
	"magneticstripe",
	"sad",
	"fullpan",
	"expirationdate",
	"expiry",
}

# Normaliza un nombre de campo para compararlo con la lista prohibida:
# minúsculas y sin separadores (_ - espacio).
normalize_field(name) := out if {
	lowered := lower(name)
	no_us := replace(lowered, "_", "")
	no_hy := replace(no_us, "-", "")
	out := replace(no_hy, " ", "")
}

field_is_forbidden(name) if {
	norm := normalize_field(name)
	some token in forbidden_field_tokens
	contains(norm, token)
}

# Extrae nombres de campo del object type, tolerando distintas formas en que
# aws/awscc expresan los fields en el plan. Cada cláusula está guardada por la
# forma concreta para que como mucho una aplique y no haya conflicto de valores.

# Forma 1: fields es un array de objetos con clave name (provider aws).
object_type_field_names(rc) := names if {
	is_array(rc.change.after.fields)
	names := {n |
		some f in rc.change.after.fields
		n := f.name
	}
}

# Forma 2: fields es un objeto {nombre: definición}.
object_type_field_names(rc) := names if {
	is_object(rc.change.after.fields)
	names := {k | some k, _ in rc.change.after.fields}
}

# Forma 3: object_type_fields es un objeto {nombre: definición} (awscc).
object_type_field_names(rc) := names if {
	not has_fields(rc)
	is_object(rc.change.after.object_type_fields)
	names := {k | some k, _ in rc.change.after.object_type_fields}
}

has_fields(rc) if is_array(rc.change.after.fields)

has_fields(rc) if is_object(rc.change.after.fields)

deny contains msg if {
	some rc in changed
	rc.type in profiles_object_type_types
	some name in object_type_field_names(rc)
	field_is_forbidden(name)
	msg := sprintf("%s: el object type no puede definir el campo %q (dato de tarjeta o autenticación — Req 8.10)", [rc.address, name])
}

# DataClassification y Compliance de los recursos de Customer Profiles.
profiles_types := profiles_domain_types | profiles_object_type_types | {"aws_customerprofiles_integration", "awscc_customerprofiles_integration"}

allowed_profiles_classification := {"confidential", "restricted", "pci"}

allowed_profiles_compliance := {"lpdp", "pci-dss"}

deny contains msg if {
	some rc in changed
	rc.type in profiles_types
	value := rc.change.after.tags_all.DataClassification
	not value in allowed_profiles_classification
	msg := sprintf("%s: DataClassification = %q debe ser confidential, restricted o pci (Req 11.3)", [rc.address, value])
}

deny contains msg if {
	some rc in changed
	rc.type in profiles_types
	value := rc.change.after.tags_all.Compliance
	not value in allowed_profiles_compliance
	msg := sprintf("%s: Compliance = %q debe ser lpdp o pci-dss (Req 11.3)", [rc.address, value])
}

# ---------------------------------------------------------------------------
# SAML (Req 10.3 — permission boundary y duración de sesión)
# ---------------------------------------------------------------------------

# El rol de federación debe llevar permission boundary.
deny contains msg if {
	some rc in changed
	rc.type == "aws_iam_role"
	contains_connect_federation(rc)
	not has_permission_boundary(rc)
	msg := sprintf("%s: el rol de federación debe tener permissions_boundary", [rc.address])
}

# permissions_boundary presente y no vacío (null/ausente/"" se tratan como falta).
has_permission_boundary(rc) if {
	pb := rc.change.after.permissions_boundary
	pb != null
	pb != ""
}

# La duración máxima de sesión no puede superar 3600 s.
deny contains msg if {
	some rc in changed
	rc.type == "aws_iam_role"
	contains_connect_federation(rc)
	rc.change.after.max_session_duration > 3600
	msg := sprintf("%s: max_session_duration = %d supera el máximo de 3600 s", [rc.address, rc.change.after.max_session_duration])
}

# Identifica el rol de federación de Connect por su nombre o su tag Name.
contains_connect_federation(rc) if contains(object.get(rc.change.after, "name", ""), "connect-federation")

contains_connect_federation(rc) if contains(object.get(rc.change.after.tags_all, "Name", ""), "connect-federation")
