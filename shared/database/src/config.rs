use std::env;

#[derive(Clone, Debug)]
pub struct DatabaseConfig {

    pub database_url: String,
}

impl DatabaseConfig {

    pub fn from_env() -> Self {

        Self {

            database_url: env::var(
                "DATABASE_URL"
            )
            .expect(
                "DATABASE_URL missing"
            ),
        }
    }
}