use serde_json::Value;

pub async fn generate_explanation(
    decisions: &Vec<Value>,
    openai_key: &str,
) -> Option<String> {

    let prompt = format!(
        "You are an MDM expert. Explain why these fields were chosen as the golden record:\n\n{}",
        serde_json::to_string_pretty(decisions).unwrap_or_default()
    );

    let client = reqwest::Client::new();

    let res = client
        .post("https://api.openai.com/v1/chat/completions")
        .bearer_auth(openai_key)
        .json(&serde_json::json!({
            "model": "gpt-4o-mini",
            "temperature": 0.2,
            "messages": [
                {"role": "system", "content": "You explain data merge decisions clearly"},
                {"role": "user", "content": prompt}
            ]
        }))
        .send()
        .await;

    match res {
        Ok(resp) => {
            let json: Value = resp.json().await.unwrap_or_default();

            Some(
                json["choices"][0]["message"]["content"]
                    .as_str()
                    .unwrap_or("No explanation generated")
                    .to_string()
            )
        }
        Err(e) => {
            println!("⚠️ AI explain failed: {:?}", e);
            None
        }
    }
}