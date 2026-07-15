// ============================================================================
// SSO Service â€” SAML 2.0 SP + SCIM token management
//
// Implements:
//   - SAML 2.0 SP metadata XML generation
//   - SAML AuthnRequest (redirect binding: deflate + base64 + urlencode)
//   - SAML Response ACS parsing + signature verification (RSA-SHA256)
//   - Per-tenant sso_configurations CRUD
//   - SCIM 2.0 bearer token issuance / verification / revocation
// ============================================================================

use anyhow::{anyhow, bail, Result};
use base64::{engine::general_purpose::STANDARD, Engine};
use chrono::Utc;
use flate2::{write::DeflateEncoder, Compression};
use quick_xml::{events::Event, Reader};
use rsa::{
    pkcs1::DecodeRsaPublicKey,
    pkcs1v15::{Signature as Pkcs1Sig, VerifyingKey},
    signature::Verifier,
    RsaPublicKey,
};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::io::Write as IoWrite;
use tracing::{info, warn};
use uuid::Uuid;
use x509_parser::prelude::*;

// â”€â”€ DB row types â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug, sqlx::FromRow, serde::Serialize, serde::Deserialize, Clone)]
pub struct SsoConfig {
    pub sso_config_id:      Uuid,
    pub tenant_id:          Uuid,
    pub provider_type:      String,
    pub is_enabled:         bool,
    pub idp_entity_id:      Option<String>,
    pub idp_sso_url:        Option<String>,
    pub idp_slo_url:        Option<String>,
    pub idp_certificate:    Option<String>,
    pub sp_entity_id:       Option<String>,
    pub sp_acs_url:         Option<String>,
    pub sp_name_id_format:  String,
    pub attribute_mappings: serde_json::Value,
    pub default_role:       String,
    pub auto_provision:     bool,
    pub auto_deprovision:   bool,
    pub group_role_mappings: serde_json::Value,
    pub created_at:         chrono::DateTime<Utc>,
    pub updated_at:         chrono::DateTime<Utc>,
}

#[derive(Debug, sqlx::FromRow, serde::Serialize)]
pub struct ScimToken {
    pub token_id:      Uuid,
    pub tenant_id:     Uuid,
    pub description:   String,
    pub created_by:    Option<Uuid>,
    pub last_used_at:  Option<chrono::DateTime<Utc>>,
    pub expires_at:    Option<chrono::DateTime<Utc>>,
    pub is_active:     bool,
    pub created_at:    chrono::DateTime<Utc>,
}

// â”€â”€ Upsert payload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug, serde::Deserialize)]
pub struct UpsertSsoConfig {
    pub provider_type:      String,
    pub is_enabled:         Option<bool>,
    pub idp_entity_id:      Option<String>,
    pub idp_sso_url:        Option<String>,
    pub idp_slo_url:        Option<String>,
    pub idp_certificate:    Option<String>,
    pub sp_entity_id:       Option<String>,
    pub sp_acs_url:         Option<String>,
    pub attribute_mappings: Option<serde_json::Value>,
    pub default_role:       Option<String>,
    pub auto_provision:     Option<bool>,
    pub auto_deprovision:   Option<bool>,
    pub group_role_mappings: Option<serde_json::Value>,
}

// â”€â”€ Parsed SAML claims (output of ACS) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Debug)]
pub struct SamlClaims {
    pub email:       String,
    pub display_name: Option<String>,
    pub groups:      Vec<String>,
    pub raw_attrs:   std::collections::HashMap<String, Vec<String>>,
}

// â”€â”€ Service â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

#[derive(Clone)]
pub struct SsoService {
    db: PgPool,
}

impl SsoService {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }

    // â”€â”€ Config CRUD â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    pub async fn get_config(&self, tenant_id: Uuid) -> Result<Option<SsoConfig>> {
        let cfg = sqlx::query_as::<_, SsoConfig>(
            "SELECT * FROM core_mdm.sso_configurations WHERE tenant_id = $1 LIMIT 1",
        )
        .bind(tenant_id)
        .fetch_optional(&self.db)
        .await?;
        Ok(cfg)
    }

    pub async fn upsert_config(
        &self,
        tenant_id: Uuid,
        created_by: Uuid,
        payload: UpsertSsoConfig,
    ) -> Result<SsoConfig> {
        let cfg = sqlx::query_as::<_, SsoConfig>(
            r#"
            INSERT INTO core_mdm.sso_configurations
                (tenant_id, provider_type, is_enabled,
                 idp_entity_id, idp_sso_url, idp_slo_url, idp_certificate,
                 sp_entity_id, sp_acs_url,
                 attribute_mappings, default_role, auto_provision, auto_deprovision,
                 group_role_mappings, created_by)
            VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
            ON CONFLICT (tenant_id, provider_type) DO UPDATE SET
                is_enabled        = COALESCE($3,  sso_configurations.is_enabled),
                idp_entity_id     = COALESCE($4,  sso_configurations.idp_entity_id),
                idp_sso_url       = COALESCE($5,  sso_configurations.idp_sso_url),
                idp_slo_url       = COALESCE($6,  sso_configurations.idp_slo_url),
                idp_certificate   = COALESCE($7,  sso_configurations.idp_certificate),
                sp_entity_id      = COALESCE($8,  sso_configurations.sp_entity_id),
                sp_acs_url        = COALESCE($9,  sso_configurations.sp_acs_url),
                attribute_mappings = COALESCE($10, sso_configurations.attribute_mappings),
                default_role      = COALESCE($11, sso_configurations.default_role),
                auto_provision    = COALESCE($12, sso_configurations.auto_provision),
                auto_deprovision  = COALESCE($13, sso_configurations.auto_deprovision),
                group_role_mappings = COALESCE($14, sso_configurations.group_role_mappings),
                updated_at        = NOW()
            RETURNING *
            "#,
        )
        .bind(tenant_id)
        .bind(&payload.provider_type)
        .bind(payload.is_enabled.unwrap_or(false))
        .bind(payload.idp_entity_id.as_deref())
        .bind(payload.idp_sso_url.as_deref())
        .bind(payload.idp_slo_url.as_deref())
        .bind(payload.idp_certificate.as_deref())
        .bind(payload.sp_entity_id.as_deref())
        .bind(payload.sp_acs_url.as_deref())
        .bind(payload.attribute_mappings.as_ref())
        .bind(payload.default_role.as_deref())
        .bind(payload.auto_provision)
        .bind(payload.auto_deprovision)
        .bind(payload.group_role_mappings.as_ref())
        .bind(created_by)
        .fetch_one(&self.db)
        .await?;
        Ok(cfg)
    }

    pub async fn delete_config(&self, tenant_id: Uuid, provider_type: &str) -> Result<()> {
        sqlx::query(
            "DELETE FROM core_mdm.sso_configurations WHERE tenant_id=$1 AND provider_type=$2",
        )
        .bind(tenant_id)
        .bind(provider_type)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    // â”€â”€ SAML SP Metadata XML â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    pub fn generate_metadata(&self, cfg: &SsoConfig, base_url: &str) -> String {
        let tenant_slug = cfg.tenant_id.to_string();
        let entity_id = cfg.sp_entity_id.clone()
            .unwrap_or_else(|| format!("{}/saml/{}/metadata", base_url, tenant_slug));
        let acs_url = cfg.sp_acs_url.clone()
            .unwrap_or_else(|| format!("{}/saml/{}/acs", base_url, tenant_slug));
        let name_id_fmt = &cfg.sp_name_id_format;

        format!(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor
    xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata"
    entityID="{entity_id}">
  <md:SPSSODescriptor
      AuthnRequestsSigned="false"
      WantAssertionsSigned="true"
      protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <md:NameIDFormat>{name_id_fmt}</md:NameIDFormat>
    <md:AssertionConsumerService
        Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
        Location="{acs_url}"
        index="1"/>
  </md:SPSSODescriptor>
</md:EntityDescriptor>"#
        )
    }

    // â”€â”€ SAML AuthnRequest â€” redirect binding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    /// Returns the full IdP SSO redirect URL (including SAMLRequest + RelayState).
    pub async fn build_authn_redirect(
        &self,
        cfg: &SsoConfig,
        base_url: &str,
        relay_state: &str,
        redirect_url: &str,
        tenant_id: Uuid,
    ) -> Result<String> {
        let idp_sso_url = cfg.idp_sso_url.as_deref()
            .ok_or_else(|| anyhow!("IdP SSO URL not configured"))?;

        let tenant_slug = tenant_id.to_string();
        let acs_url = cfg.sp_acs_url.clone()
            .unwrap_or_else(|| format!("{}/saml/{}/acs", base_url, tenant_slug));
        let sp_entity_id = cfg.sp_entity_id.clone()
            .unwrap_or_else(|| format!("{}/saml/{}/metadata", base_url, tenant_slug));
        let request_id = format!("_azile_{}", Uuid::new_v4().to_string().replace('-', ""));
        let issue_instant = Utc::now().format("%Y-%m-%dT%H:%M:%SZ");

        let xml = format!(
            r#"<samlp:AuthnRequest xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" ID="{request_id}" Version="2.0" IssueInstant="{issue_instant}" Destination="{idp_sso_url}" ProtocolBinding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" AssertionConsumerServiceURL="{acs_url}"><saml:Issuer>{sp_entity_id}</saml:Issuer><samlp:NameIDPolicy Format="{name_id_fmt}" AllowCreate="true"/></samlp:AuthnRequest>"#,
            name_id_fmt = cfg.sp_name_id_format,
        );

        // Persist session for relay_state â†’ redirect_url mapping
        sqlx::query(
            r#"INSERT INTO core_mdm.saml_sessions (relay_state, tenant_id, redirect_url)
               VALUES ($1, $2, $3)
               ON CONFLICT (relay_state) DO UPDATE SET redirect_url=$3, expires_at=NOW()+INTERVAL '10 minutes'"#,
        )
        .bind(relay_state)
        .bind(tenant_id)
        .bind(redirect_url)
        .execute(&self.db)
        .await?;

        // Deflate (raw DEFLATE, not zlib, not gzip) + standard base64 + percent-encode
        // per SAML 2.0 HTTP Redirect Binding spec section 3.4.4.1
        let mut encoder = DeflateEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(xml.as_bytes())?;
        let compressed = encoder.finish()?;

        let saml_b64 = STANDARD.encode(&compressed);
        let saml_encoded = percent_encode_saml(&saml_b64);
        let relay_encoded = percent_encode_saml(relay_state);

        let connector = if idp_sso_url.contains('?') { '&' } else { '?' };
        Ok(format!(
            "{idp_sso_url}{connector}SAMLRequest={saml_encoded}&RelayState={relay_encoded}"
        ))
    }

    // â”€â”€ SAML ACS â€” parse response, verify, return claims â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    pub async fn process_acs_response(
        &self,
        saml_response_b64: &str,
        relay_state: &str,
        cfg: &SsoConfig,
    ) -> Result<(SamlClaims, String)> {
        // 1. Retrieve relay state session
        let redirect_url: Option<String> = sqlx::query_scalar(
            r#"
            DELETE FROM core_mdm.saml_sessions
            WHERE relay_state = $1 AND tenant_id = $2 AND expires_at > NOW()
            RETURNING redirect_url
            "#,
        )
        .bind(relay_state)
        .bind(cfg.tenant_id)
        .fetch_optional(&self.db)
        .await?;

        let redirect = redirect_url.unwrap_or_else(|| "/dashboard".to_string());

        // 2. Base64-decode the SAML response
        let xml_bytes = STANDARD
            .decode(saml_response_b64.trim())
            .map_err(|e| anyhow!("SAML response base64 decode failed: {}", e))?;
        let xml_str = String::from_utf8(xml_bytes)
            .map_err(|e| anyhow!("SAML response not valid UTF-8: {}", e))?;

        // 3. Verify signature if cert is configured
        if let Some(ref cert_pem) = cfg.idp_certificate {
            if !cert_pem.trim().is_empty() {
                match verify_saml_signature(&xml_str, cert_pem) {
                    Ok(()) => info!("SAML signature verified"),
                    Err(e) => {
                        warn!(error=%e, "SAML signature verification failed");
                        bail!("SAML signature invalid: {}", e);
                    }
                }
            } else {
                warn!("No IdP certificate configured â€” SAML signature NOT verified");
            }
        } else {
            warn!("No IdP certificate configured â€” SAML signature NOT verified");
        }

        // 4. Parse claims from XML
        let claims = parse_saml_response_claims(&xml_str, cfg)?;

        // 5. Validate time conditions
        validate_saml_conditions(&xml_str)?;

        Ok((claims, redirect))
    }

    // â”€â”€ SCIM Token Management â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

    /// Creates a new SCIM token. Returns (row, raw_token) â€” raw token shown once only.
    pub async fn create_scim_token(
        &self,
        tenant_id: Uuid,
        created_by: Uuid,
        description: &str,
        expires_at: Option<chrono::DateTime<Utc>>,
    ) -> Result<(ScimToken, String)> {
        let raw_token = {
            use rand::Rng;
            let bytes: Vec<u8> = rand::thread_rng().sample_iter(rand::distributions::Standard).take(32).collect();
            format!("azile_scim_{}", hex::encode(&bytes))
        };

        let mut hasher = Sha256::new();
        hasher.update(raw_token.as_bytes());
        let token_hash = hex::encode(hasher.finalize());

        let row = sqlx::query_as::<_, ScimToken>(
            r#"
            INSERT INTO core_mdm.scim_tokens
                (tenant_id, token_hash, description, created_by, expires_at)
            VALUES ($1, $2, $3, $4, $5)
            RETURNING *
            "#,
        )
        .bind(tenant_id)
        .bind(&token_hash)
        .bind(description)
        .bind(created_by)
        .bind(expires_at)
        .fetch_one(&self.db)
        .await?;

        Ok((row, raw_token))
    }

    pub async fn list_scim_tokens(&self, tenant_id: Uuid) -> Result<Vec<ScimToken>> {
        let rows = sqlx::query_as::<_, ScimToken>(
            "SELECT * FROM core_mdm.scim_tokens WHERE tenant_id=$1 ORDER BY created_at DESC",
        )
        .bind(tenant_id)
        .fetch_all(&self.db)
        .await?;
        Ok(rows)
    }

    pub async fn revoke_scim_token(&self, token_id: Uuid, tenant_id: Uuid) -> Result<()> {
        sqlx::query(
            "UPDATE core_mdm.scim_tokens SET is_active=false WHERE token_id=$1 AND tenant_id=$2",
        )
        .bind(token_id)
        .bind(tenant_id)
        .execute(&self.db)
        .await?;
        Ok(())
    }

    /// Verifies a SCIM bearer token and returns the tenant_id it belongs to.
    pub async fn verify_scim_token(&self, raw_token: &str) -> Result<Uuid> {
        let mut hasher = Sha256::new();
        hasher.update(raw_token.as_bytes());
        let token_hash = hex::encode(hasher.finalize());

        let row: Option<(Uuid, Option<chrono::DateTime<Utc>>)> = sqlx::query_as(
            r#"
            UPDATE core_mdm.scim_tokens
            SET last_used_at = NOW()
            WHERE token_hash = $1 AND is_active = true
            RETURNING tenant_id, expires_at
            "#,
        )
        .bind(&token_hash)
        .fetch_optional(&self.db)
        .await?;

        match row {
            None => bail!("Invalid or revoked SCIM token"),
            Some((_tenant_id, Some(exp))) if exp < Utc::now() => {
                bail!("SCIM token expired")
            }
            Some((tenant_id, _)) => Ok(tenant_id),
        }
    }
}

// â”€â”€ SAML XML Signature Verification â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//
// Implements RSA-SHA256 signature verification as used by Okta, Azure AD,
// Google Workspace, and ADFS.
//
// Limitation: uses the raw bytes of <ds:SignedInfo> as-extracted from the
// XML response, rather than a full exclusive-C14N implementation. This works
// for all major enterprise IdPs because they produce consistently-ordered XML.
// A full exc-C14N implementation is a future enhancement.

fn verify_saml_signature(xml: &str, cert_pem: &str) -> Result<()> {
    // Extract raw SignedInfo bytes and SignatureValue
    let (signed_info_bytes, sig_b64) = extract_signed_info_and_sig(xml)
        .ok_or_else(|| anyhow!("Could not extract ds:SignedInfo or ds:SignatureValue from SAML response"))?;

    // Decode signature
    let sig_bytes = STANDARD.decode(sig_b64.trim())
        .map_err(|e| anyhow!("SignatureValue base64 decode: {}", e))?;

    // Parse IdP certificate (strip PEM header/footer, decode base64 DER)
    let cert_der = decode_pem_cert(cert_pem)?;

    // Parse X.509 certificate to get RSA public key
    let (_, cert) = X509Certificate::from_der(&cert_der)
        .map_err(|e| anyhow!("X.509 parse error: {:?}", e))?;

    // For RSA, subject_public_key bit-string data is PKCS#1 DER
    let spki = cert.public_key();
    let pk_der = spki.subject_public_key.as_ref();

    let public_key = RsaPublicKey::from_pkcs1_der(pk_der)
        .map_err(|e| anyhow!("RSA public key parse error: {}", e))?;

    let verifying_key: VerifyingKey<Sha256> = VerifyingKey::new(public_key);
    let sig = Pkcs1Sig::try_from(sig_bytes.as_slice())
        .map_err(|e| anyhow!("Signature decode error: {}", e))?;

    verifying_key
        .verify(&signed_info_bytes, &sig)
        .map_err(|e| anyhow!("RSA-SHA256 signature mismatch: {}", e))?;

    Ok(())
}

/// Extracts the raw bytes of <ds:SignedInfo>â€¦</ds:SignedInfo> and the
/// ds:SignatureValue text from the SAML XML string.
fn extract_signed_info_and_sig(xml: &str) -> Option<(Vec<u8>, String)> {
    // Find ds:SignedInfo start and end positions
    let si_open = xml.find("<ds:SignedInfo")?;
    let si_close_tag = "</ds:SignedInfo>";
    let si_end = xml.find(si_close_tag)? + si_close_tag.len();
    let signed_info_bytes = xml[si_open..si_end].as_bytes().to_vec();

    // Extract ds:SignatureValue text
    let sv_open = xml.find("<ds:SignatureValue")?;
    let sv_content_start = xml[sv_open..].find('>')? + sv_open + 1;
    let sv_close = xml.find("</ds:SignatureValue>")?;
    let sig_b64 = xml[sv_content_start..sv_close].trim().to_string();

    Some((signed_info_bytes, sig_b64))
}

/// Decodes PEM or bare-base64 certificate data into DER bytes.
fn decode_pem_cert(pem_or_b64: &str) -> Result<Vec<u8>> {
    let stripped = pem_or_b64
        .lines()
        .filter(|l| !l.starts_with("-----"))
        .collect::<Vec<_>>()
        .join("");
    STANDARD.decode(stripped.trim())
        .map_err(|e| anyhow!("Certificate base64 decode failed: {}", e))
}

// â”€â”€ SAML Response XML Parsing â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

fn parse_saml_response_claims(xml: &str, cfg: &SsoConfig) -> Result<SamlClaims> {
    let attr_mappings = &cfg.attribute_mappings;
    let email_attr = attr_mappings
        .get("email")
        .and_then(|v| v.as_str())
        .unwrap_or("NameID");
    let name_attr = attr_mappings
        .get("name")
        .and_then(|v| v.as_str())
        .unwrap_or("displayName");
    let groups_attr = attr_mappings
        .get("groups")
        .and_then(|v| v.as_str())
        .unwrap_or("memberOf");

    let mut reader = Reader::from_str(xml);
    reader.trim_text(true);

    let mut in_name_id        = false;
    let mut in_attr_name      = false;
    let mut in_attr_value     = false;
    let mut current_attr_name = String::new();

    let mut name_id           = String::new();
    let mut attrs: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();

    let mut buf = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(ref e)) => {
                let local = local_name(e.name().as_ref());
                match local.as_str() {
                    "NameID" => in_name_id = true,
                    "Attribute" => {
                        in_attr_name = true;
                        current_attr_name.clear();
                        for attr in e.attributes().flatten() {
                            let key = local_name(attr.key.as_ref());
                            if key == "Name" || key == "FriendlyName" && current_attr_name.is_empty() {
                                current_attr_name = String::from_utf8_lossy(&attr.value).into_owned();
                            }
                        }
                    }
                    "AttributeValue" if in_attr_name => in_attr_value = true,
                    _ => {}
                }
            }
            Ok(Event::Empty(ref e)) => {
                let local = local_name(e.name().as_ref());
                if local == "StatusCode" {
                    for attr in e.attributes().flatten() {
                        let key = local_name(attr.key.as_ref());
                        if key == "Value" {
                            let val = String::from_utf8_lossy(&attr.value);
                            if !val.contains("Success") {
                                return Err(anyhow!("SAML status not Success: {}", val));
                            }
                        }
                    }
                }
            }
            Ok(Event::Text(ref e)) => {
                let text = e.unescape().unwrap_or_default().into_owned();
                if in_name_id {
                    name_id = text;
                } else if in_attr_value {
                    attrs.entry(current_attr_name.clone())
                        .or_default()
                        .push(text);
                }
            }
            Ok(Event::End(ref e)) => {
                let local = local_name(e.name().as_ref());
                match local.as_str() {
                    "NameID"         => in_name_id   = false,
                    "Attribute"      => { in_attr_name = false; in_attr_value = false; }
                    "AttributeValue" => in_attr_value = false,
                    _ => {}
                }
            }
            Ok(Event::Eof) => break,
            Err(e) => bail!("XML parse error at position {}: {}", reader.buffer_position(), e),
            _ => {}
        }
        buf.clear();
    }

    // Determine email â€” prefer NameID, fall back to attribute mapping
    let email = if name_id.contains('@') {
        name_id.clone()
    } else if let Some(vals) = attrs.get(email_attr) {
        vals.first().cloned().unwrap_or_default()
    } else {
        bail!("Could not extract email from SAML assertion (NameID='{}')", name_id)
    };

    if email.is_empty() || !email.contains('@') {
        bail!("SAML assertion did not provide a valid email address");
    }

    let display_name = attrs.get(name_attr).and_then(|v| v.first()).cloned();
    let groups = attrs.get(groups_attr).cloned().unwrap_or_default();

    Ok(SamlClaims {
        email,
        display_name,
        groups,
        raw_attrs: attrs,
    })
}

/// Validate NotBefore / NotOnOrAfter conditions with Â±5 min clock skew tolerance.
fn validate_saml_conditions(xml: &str) -> Result<()> {
    let now = Utc::now();
    let skew = chrono::Duration::minutes(5);

    let mut reader = Reader::from_str(xml);
    reader.trim_text(true);
    let mut buf = Vec::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Empty(ref e)) | Ok(Event::Start(ref e)) => {
                let local = local_name(e.name().as_ref());
                if local == "Conditions" {
                    for attr in e.attributes().flatten() {
                        let key = local_name(attr.key.as_ref());
                        let val = String::from_utf8_lossy(&attr.value).into_owned();
                        if key == "NotBefore" {
                            if let Ok(not_before) = chrono::DateTime::parse_from_rfc3339(&val) {
                                if now < not_before.with_timezone(&Utc) - skew {
                                    bail!("SAML assertion not yet valid (NotBefore: {})", val);
                                }
                            }
                        }
                        if key == "NotOnOrAfter" {
                            if let Ok(not_after) = chrono::DateTime::parse_from_rfc3339(&val) {
                                if now > not_after.with_timezone(&Utc) + skew {
                                    bail!("SAML assertion expired (NotOnOrAfter: {})", val);
                                }
                            }
                        }
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
        buf.clear();
    }
    Ok(())
}

/// Percent-encodes a string for use in a SAML redirect binding query parameter.
/// Encodes all chars except unreserved (RFC 3986): A-Z a-z 0-9 - _ . ~
fn percent_encode_saml(input: &str) -> String {
    let mut out = String::with_capacity(input.len() * 2);
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9'
            | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char);
            }
            other => {
                out.push('%');
                out.push_str(&format!("{:02X}", other));
            }
        }
    }
    out
}

/// Strips XML namespace prefix â€” returns the local name.
fn local_name(name: &[u8]) -> String {
    let s = std::str::from_utf8(name).unwrap_or("");
    let local = if let Some(pos) = s.rfind(':') { &s[pos + 1..] } else { s };
    local.to_string()
}
