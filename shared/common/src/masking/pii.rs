pub fn mask_email(
    value: &str
) -> String {

    let parts: Vec<&str> =
        value.split('@').collect();

    if parts.len() != 2 {
        return "****".to_string();
    }

    format!(
        "{}***@{}",
        &parts[0][0..1],
        parts[1]
    )
}

pub fn mask_phone(
    value: &str
) -> String {

    if value.len() < 4 {
        return "****".to_string();
    }

    format!(
        "******{}",
        &value[value.len()-4..]
    )
}

pub fn mask_pan(
    value: &str
) -> String {

    if value.len() < 4 {
        return "****".to_string();
    }

    format!(
        "********{}",
        &value[value.len()-4..]
    )
}