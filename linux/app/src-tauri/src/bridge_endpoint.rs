pub const LOOPBACK_HOST: &str = "127.0.0.1";
pub const DEFAULT_BRIDGE_PORT: u16 = 24_080;

pub fn bridge_websocket_url(port: u16) -> Result<url::Url, url::ParseError> {
    url::Url::parse(&format!("ws://{LOOPBACK_HOST}:{port}/"))
}
