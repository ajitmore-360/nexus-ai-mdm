use reqwest::Client;
use serde_json::Value;

pub async fn proxy_mdm_request(
    client: &Client,
    base_url: &str,
    endpoint: &str,
    payload: Value,
) -> Result<Value, String> {

    let url = format!("{}/{}", base_url, endpoint);

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

    Ok(json)
}