package mdm.policy

import future.keywords.if
import future.keywords.in

# ============================================================================
# Nexus AI MDM — Base Policy
#
# Evaluates entity access, merge, and distribution operations.
# Override per-tenant via additional policies loaded via the API.
# ============================================================================

default allow = true
default masked_fields = []
default required_fields = []
default warnings = []

# ── Field masking ─────────────────────────────────────────────────────────────

# Mask SSN from non-admin users
masked_fields[field] {
    field := "ssn"
    input.user_role != "admin"
    input.user_role != "compliance"
}

# Mask tax_id from viewer role
masked_fields[field] {
    field := "tax_id"
    input.user_role == "viewer"
}

# Mask bank_account from all non-admin roles on read
masked_fields[field] {
    field := "bank_account"
    input.operation == "read"
    input.user_role != "admin"
}

# ── Required fields ───────────────────────────────────────────────────────────

# Customer entities require email or phone
required_fields[field] {
    input.entity_type == "customer"
    input.operation == "write"
    field := "email"
    not has_field(input.entity, "email")
    not has_field(input.entity, "phone")
}

# ── Access control ────────────────────────────────────────────────────────────

# Viewers cannot perform write operations
allow = false if {
    input.operation in ["write", "merge", "delete"]
    input.user_role == "viewer"
}

# Viewers cannot export
allow = false if {
    input.operation == "export"
    input.user_role == "viewer"
}

# ── Warnings ──────────────────────────────────────────────────────────────────

warnings[msg] {
    input.entity_type == "customer"
    not has_field(input.entity, "email")
    not has_field(input.entity, "phone")
    msg := "Customer entity has neither email nor phone — contact data is incomplete"
}

warnings[msg] {
    input.operation == "merge"
    not input.entity.tax_id
    msg := "Merging entities without a Tax ID — consider adding tax_id to improve survivorship accuracy"
}

# ── Helpers ───────────────────────────────────────────────────────────────────

has_field(obj, field) {
    _ := obj[field]
}
