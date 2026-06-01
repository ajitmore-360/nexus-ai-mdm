use reqwest::Client;
use serde_json::Value;

pub async fn validate_policy(
    client: &Client,
    base_url: &str,
    payload: Value,
) -> Result<bool, String> {

    let url = format!("{}/validate", base_url);

    let res = client
        .post(url)
        .json(&payload)
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let json = res
        .json::<Value>()
        .await
        .map_err(|e| e.to_string())?;

    Ok(
        json["allowed"]
            .as_bool()
            .unwrap_or(false)
    )
}