// WebSocket client to the local `clawix-bridge` daemon. Mirrors what
// the Mac GUI's DaemonBridgeClient does: connects to the canonical loopback
// bridge endpoint, sends the auth frame with the bridge token from
// `~/.clawix/state/bridge-token`, and dispatches inbound frames as Tauri
// events the SolidJS frontend subscribes to.

use anyhow::{anyhow, Context, Result};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Emitter};
use tokio::sync::Mutex;
use tokio_tungstenite::tungstenite::Message;
use tracing::{debug, info, warn};

const BRIDGE_SCHEMA_VERSION: u8 = 1;
const RECONNECT_BACKOFF_MS: u64 = 1500;
const FRAME_BATCH_WINDOW_MS: u64 = 16;

#[derive(Default)]
pub struct DaemonClient {
    write_tx: Option<tokio::sync::mpsc::Sender<Message>>,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct PairingPayload {
    pub token: String,
    pub short_code: String,
    pub qr_json: String,
}

#[derive(Serialize)]
pub struct ChatBrief {
    pub id: String,
    pub title: String,
    pub last_message: Option<String>,
    pub has_active_turn: bool,
}

impl DaemonClient {
    pub fn new() -> Self {
        Self { write_tx: None }
    }

    pub async fn get_chats(&self) -> Result<Vec<crate::commands::WireSessionBrief>> {
        self.send_intent(serde_json::json!({ "type": "listSessions" }))
            .await?;
        Ok(Vec::new())
    }

    pub async fn get_projects(&self) -> Result<Vec<crate::commands::WireProjectBrief>> {
        self.send_intent(serde_json::json!({ "type": "listProjects" }))
            .await?;
        Ok(Vec::new())
    }

    pub async fn open_session(&self, session_id: &str) -> Result<serde_json::Value> {
        self.send_intent(serde_json::json!({
            "type": "openSession",
            "sessionId": session_id,
            "limit": 60,
        }))
        .await
    }

    pub async fn load_older_messages(
        &self,
        session_id: &str,
        before_message_id: &str,
    ) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "loadOlderMessages",
            "sessionId": session_id,
            "beforeMessageId": before_message_id,
            "limit": 40,
        }))
        .await?;
        Ok(())
    }

    pub async fn send_message(
        &self,
        session_id: Option<&str>,
        text: &str,
        attachments: Vec<serde_json::Value>,
    ) -> Result<serde_json::Value> {
        let body = if let Some(id) = session_id {
            serde_json::json!({ "type": "sendMessage", "sessionId": id, "text": text, "attachments": attachments })
        } else {
            serde_json::json!({
                "type": "newSession",
                "sessionId": uuid_v4(),
                "text": text,
                "attachments": attachments
            })
        };
        self.send_intent(body).await
    }

    pub async fn interrupt_turn(&self, session_id: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "interruptTurn",
            "sessionId": session_id
        }))
        .await?;
        Ok(())
    }

    pub async fn edit_prompt(&self, session_id: &str, message_id: &str, text: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "editPrompt",
            "sessionId": session_id,
            "messageId": message_id,
            "text": text
        }))
        .await?;
        Ok(())
    }

    pub async fn set_pinned(&self, session_id: &str, pinned: bool) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": if pinned { "pinSession" } else { "unpinSession" },
            "sessionId": session_id
        }))
        .await?;
        Ok(())
    }

    pub async fn set_archived(&self, session_id: &str, archived: bool) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": if archived { "archiveSession" } else { "unarchiveSession" },
            "sessionId": session_id
        }))
        .await?;
        Ok(())
    }

    pub async fn rename_session(&self, session_id: &str, title: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "renameSession",
            "sessionId": session_id,
            "title": title
        }))
        .await?;
        Ok(())
    }

    pub async fn read_file(&self, path: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "readFile",
            "path": path
        }))
        .await?;
        Ok(())
    }

    pub async fn request_generated_image(&self, path: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "requestGeneratedImage",
            "path": path
        }))
        .await?;
        Ok(())
    }

    pub async fn request_rollout_attachment(&self, attachment_id: &str) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "requestRolloutAttachment",
            "attachmentId": attachment_id
        }))
        .await?;
        Ok(())
    }

    pub async fn request_audio(&self, audio_id: &str) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioGetBytes",
            "requestId": request_id,
            "audioId": audio_id,
            "appId": "clawix"
        }))
        .await?;

        self.send_intent(serde_json::json!({
            "type": "requestAudio",
            "audioId": audio_id
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn audio_get(&self, audio_id: &str, app_id: &str) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioGet",
            "requestId": request_id,
            "audioId": audio_id,
            "appId": app_id
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn audio_register(&self, request: serde_json::Value) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioRegister",
            "requestId": request_id,
            "request": request
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn audio_attach_transcript(
        &self,
        audio_id: &str,
        transcript: serde_json::Value,
    ) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioAttachTranscript",
            "requestId": request_id,
            "audioId": audio_id,
            "transcript": transcript
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn audio_list(&self, filter: serde_json::Value) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioList",
            "requestId": request_id,
            "filter": filter
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn audio_delete(&self, audio_id: &str, app_id: &str) -> Result<String> {
        let request_id = uuid_v4();
        self.send_intent(serde_json::json!({
            "type": "audioDelete",
            "requestId": request_id,
            "audioId": audio_id,
            "appId": app_id
        }))
        .await?;
        Ok(request_id)
    }

    pub async fn transcribe_audio(
        &self,
        audio_base64: &str,
        mime_type: &str,
        language: Option<&str>,
    ) -> Result<String> {
        let request_id = uuid_v4();
        let mut frame = serde_json::json!({
            "type": "transcribeAudio",
            "requestId": request_id,
            "audioBase64": audio_base64,
            "mimeType": mime_type
        });
        if let Some(language) = language {
            frame["language"] = serde_json::Value::String(language.to_string());
        }
        self.send_intent(frame).await?;
        Ok(request_id)
    }

    pub async fn request_rate_limits(&self) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "requestRateLimits"
        }))
        .await?;
        Ok(())
    }

    pub async fn request_clawjs_service_statuses(&self) -> Result<()> {
        self.send_intent(serde_json::json!({
            "type": "requestClawJSServiceStatuses"
        }))
        .await?;
        Ok(())
    }

    pub async fn start_pairing(&self) -> Result<PairingPayload> {
        let _ = self
            .send_intent(serde_json::json!({
                "type": "pairingStart"
            }))
            .await;

        let state_dir = state_dir();
        let token = std::fs::read_to_string(state_dir.join("bridge-token"))
            .with_context(|| "reading bridge token from ~/.clawix/state/bridge-token")?
            .trim()
            .to_string();
        let short_code = std::fs::read_to_string(state_dir.join("bridge-shortcode"))
            .unwrap_or_default()
            .trim()
            .to_string();
        let qr_json = serde_json::json!({
            "v": BRIDGE_SCHEMA_VERSION,
            "host": pairing_host(),
            "port": DEFAULT_PORT,
            "token": &token,
            "shortCode": &short_code,
        })
        .to_string();
        Ok(PairingPayload {
            token,
            short_code,
            qr_json,
        })
    }

    async fn send_intent(&self, body: serde_json::Value) -> Result<serde_json::Value> {
        let tx = self
            .write_tx
            .as_ref()
            .ok_or_else(|| anyhow!("daemon not connected"))?;
        let frame = bridge_frame(body)?;
        tx.send(Message::Text(frame.to_string()))
            .await
            .map_err(|e| anyhow!("send: {e}"))?;
        Ok(serde_json::Value::Null)
    }
}

pub async fn connect_and_run(client: Arc<Mutex<DaemonClient>>, app: AppHandle) -> Result<()> {
    loop {
        let url = crate::bridge_endpoint::bridge_websocket_url(
            crate::bridge_endpoint::DEFAULT_BRIDGE_PORT,
        )?;
        match tokio_tungstenite::connect_async(url.as_str()).await {
            Ok((ws, _)) => {
                info!(
                    "daemon connected at {}",
                    crate::bridge_endpoint::DEFAULT_BRIDGE_PORT
                );
                let (mut write, mut read) = ws.split();
                let (tx, mut rx) = tokio::sync::mpsc::channel::<Message>(64);
                {
                    let mut guard = client.lock().await;
                    guard.write_tx = Some(tx.clone());
                }
                // Auth frame
                if let Ok(bearer) = read_bearer() {
                    let auth = serde_json::json!({
                        "schemaVersion": BRIDGE_SCHEMA_VERSION,
                        "type": "auth",
                        "token": bearer,
                        "deviceName": hostname(),
                        "clientKind": "desktop",
                        "clientId": "clawix.linux.desktop",
                        "installationId": persisted_id("bridge-installation-id"),
                        "deviceId": persisted_id("bridge-device-id")
                    });
                    let _ = write.send(Message::Text(auth.to_string())).await;
                }
                // Spawn the writer pump
                let writer_task = tokio::spawn(async move {
                    while let Some(msg) = rx.recv().await {
                        if write.send(msg).await.is_err() {
                            break;
                        }
                    }
                });
                // Reader: batch incoming frames into 16ms windows so we
                // don't spam the webview IPC during heavy token streaming.
                let mut batch: Vec<serde_json::Value> = Vec::with_capacity(64);
                let mut flush = tokio::time::interval(Duration::from_millis(FRAME_BATCH_WINDOW_MS));
                flush.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
                loop {
                    tokio::select! {
                        msg = read.next() => {
                            match msg {
                                Some(Ok(Message::Text(text))) => {
                                    if let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) {
                                        batch.push(value);
                                    }
                                }
                                Some(Ok(Message::Binary(bin))) => {
                                    if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bin) {
                                        batch.push(value);
                                    }
                                }
                                Some(Ok(Message::Close(_))) | None => {
                                    debug!("daemon ws closed");
                                    break;
                                }
                                Some(Ok(_)) => {}
                                Some(Err(e)) => {
                                    warn!(?e, "ws read error");
                                    break;
                                }
                            }
                        }
                        _ = flush.tick(), if !batch.is_empty() => {
                            let drained: Vec<_> = batch.drain(..).collect();
                            let _ = app.emit("bridge:frames", drained);
                        }
                    }
                }
                writer_task.abort();
                {
                    let mut guard = client.lock().await;
                    guard.write_tx = None;
                }
            }
            Err(e) => {
                debug!(?e, "daemon connect failed, retrying");
            }
        }
        tokio::time::sleep(Duration::from_millis(RECONNECT_BACKOFF_MS)).await;
    }
}

fn read_bearer() -> Result<String> {
    let path = state_dir().join("bridge-token");
    Ok(std::fs::read_to_string(path)?.trim().to_string())
}

fn state_dir() -> PathBuf {
    dirs::home_dir()
        .map(|h| h.join(".clawix").join("state"))
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

fn bridge_frame(body: Value) -> Result<Value> {
    let mut object = body
        .as_object()
        .cloned()
        .ok_or_else(|| anyhow!("bridge frame body must be a JSON object"))?;
    object.insert(
        "schemaVersion".to_string(),
        Value::from(BRIDGE_SCHEMA_VERSION),
    );
    Ok(Value::Object(object))
}

fn persisted_id(name: &str) -> String {
    let dir = state_dir();
    let path = dir.join(name);
    if let Ok(existing) = std::fs::read_to_string(&path) {
        let trimmed = existing.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    let value = uuid_v4();
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(path, format!("{value}\n"));
    value
}

fn hostname() -> String {
    nix::unistd::gethostname()
        .ok()
        .and_then(|s| s.into_string().ok())
        .unwrap_or_else(|| "linux".to_string())
}

fn pairing_host() -> String {
    std::net::UdpSocket::bind("0.0.0.0:0")
        .and_then(|socket| {
            let _ = socket.connect("8.8.8.8:80");
            socket.local_addr()
        })
        .map(|addr| addr.ip().to_string())
        .unwrap_or_else(|_| crate::bridge_endpoint::LOOPBACK_HOST.to_string())
}

fn uuid_v4() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    format!("{:032x}", nanos)
}
