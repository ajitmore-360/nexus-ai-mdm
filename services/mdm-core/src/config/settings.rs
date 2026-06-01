use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Settings {

    pub server: ServerSettings,

    pub database: DatabaseSettings,

    pub application: ApplicationSettings,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ServerSettings {

    pub host: String,

    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseSettings {

    pub url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ApplicationSettings {

    pub environment: String,

    pub service_name: String,
}

impl Settings {

    pub fn load()
    -> anyhow::Result<Self> {

        let environment =
            std::env::var("APP_ENV")
                .unwrap_or_else(|_| {
                    "local".to_string()
                });

        let config =
            config::Config::builder()

                .add_source(
                    config::File::with_name(
                        &format!(
                            "configs/{}",
                            environment
                        )
                    )
                )

                .add_source(
                    config::Environment::default()
                )

                .build()?;

        Ok(
            config
                .try_deserialize()?
        )
    }
}