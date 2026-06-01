use crate::{
    config::settings::Settings,
    services::ServiceClients,
};

#[derive(Clone)]
pub struct AppState {
    pub settings: Settings,
    pub services: ServiceClients,
}