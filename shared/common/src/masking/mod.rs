pub fn mask_email(
    value: &str,
) -> String {

    let parts:
        Vec<&str> =
        value.split('@').collect();

    if parts.len() != 2 {
        return "***".to_string();
    }

    let username =
        parts[0];

    let domain =
        parts[1];

    let masked_username =
        if username.len() <= 2 {

            "**".to_string()

        } else {

            format!(
                "{}***{}",
                &username[..1],
                &username[
                    username.len()-1..
                ]
            )
        };

    format!(
        "{}@{}",
        masked_username,
        domain
    )
}

pub fn mask_phone(
    value: &str,
) -> String {

    if value.len() < 4 {
        return "****".to_string();
    }

    format!(
        "******{}",
        &value[
            value.len()-4..
        ]
    )
}