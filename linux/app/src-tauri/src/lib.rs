// Clawix Linux runtime entry. Wires Tauri plugins, mounts the system
// tray, brings up the WebSocket bridge to the local `clawix-bridge`
// daemon, and exposes Rust commands to the SolidJS frontend.

mod chat_db;
mod daemon_client;
mod dictation;
mod selection_sniffer;
mod service_manager;
mod shortcuts;
mod text_injector;
mod tray;

use std::sync::Arc;
use tauri::Manager;
use tokio::sync::Mutex;
use tracing_subscriber::EnvFilter;

pub struct AppState {
    pub daemon: Arc<Mutex<daemon_client::DaemonClient>>,
    pub db: Arc<chat_db::ChatDb>,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let db = Arc::new(chat_db::ChatDb::open_default().expect("chat db open"));
    let daemon = Arc::new(Mutex::new(daemon_client::DaemonClient::new()));

    tauri::Builder::default()
        .plugin(tauri_plugin_window_state::Builder::new().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .manage(AppState {
            daemon: daemon.clone(),
            db: db.clone(),
        })
        .setup(move |app| {
            let handle = app.handle().clone();
            tray::install(&handle)?;
            shortcuts::install(&handle)?;
            service_manager::ensure_daemon_running()?;
            let daemon_handle = handle.clone();
            let daemon_arc = daemon.clone();
            tauri::async_runtime::spawn(async move {
                if let Err(e) = daemon_client::connect_and_run(daemon_arc, daemon_handle).await {
                    tracing::error!(?e, "daemon connection terminated");
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_chats,
            commands::get_projects,
            commands::open_session,
            commands::load_older_messages,
            commands::send_message,
            commands::interrupt_turn,
            commands::edit_prompt,
            commands::pin_session,
            commands::unpin_session,
            commands::archive_session,
            commands::unarchive_session,
            commands::rename_session,
            commands::read_file,
            commands::request_generated_image,
            commands::request_rollout_attachment,
            commands::request_audio,
            commands::audio_get,
            commands::audio_register,
            commands::audio_attach_transcript,
            commands::audio_list,
            commands::audio_delete,
            commands::transcribe_audio,
            commands::request_rate_limits,
            commands::request_clawjs_service_statuses,
            commands::start_pairing,
            commands::list_audio_inputs,
            commands::start_dictation,
            commands::stop_dictation,
            commands::inject_text,
            commands::read_primary_selection,
            commands::open_quickask,
            commands::daemon_status,
            commands::set_setting,
            commands::get_setting,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

mod commands {
    use super::AppState;
    use crate::{daemon_client, dictation, selection_sniffer, service_manager, text_injector};
    use serde::{Deserialize, Serialize};
    use tauri::{Manager, State};

    #[derive(Serialize)]
    pub struct WireSessionBrief {
        pub id: String,
        pub title: String,
        pub last_message: Option<String>,
        pub has_active_turn: bool,
    }

    #[derive(Serialize)]
    pub struct WireProjectBrief {
        pub id: String,
        pub title: String,
        pub cwd: Option<String>,
    }

    #[tauri::command]
    pub async fn get_chats(state: State<'_, AppState>) -> Result<Vec<WireSessionBrief>, String> {
        let client = state.daemon.lock().await;
        client.get_chats().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn get_projects(state: State<'_, AppState>) -> Result<Vec<WireProjectBrief>, String> {
        let client = state.daemon.lock().await;
        client.get_projects().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn open_session(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<serde_json::Value, String> {
        let client = state.daemon.lock().await;
        client.open_session(&session_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn load_older_messages(
        session_id: String,
        before_message_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client
            .load_older_messages(&session_id, &before_message_id)
            .await
            .map_err(|e| e.to_string())
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    pub struct SendMessageArgs {
        pub session_id: Option<String>,
        pub text: String,
        #[serde(default)]
        pub attachments: Vec<serde_json::Value>,
    }

    #[tauri::command]
    pub async fn send_message(
        args: SendMessageArgs,
        state: State<'_, AppState>,
    ) -> Result<serde_json::Value, String> {
        let client = state.daemon.lock().await;
        client
            .send_message(args.session_id.as_deref(), &args.text, args.attachments)
            .await
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn interrupt_turn(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.interrupt_turn(&session_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn edit_prompt(
        session_id: String,
        message_id: String,
        text: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client
            .edit_prompt(&session_id, &message_id, text.trim())
            .await
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn pin_session(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.set_pinned(&session_id, true).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn unpin_session(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.set_pinned(&session_id, false).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn archive_session(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.set_archived(&session_id, true).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn unarchive_session(
        session_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.set_archived(&session_id, false).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn rename_session(
        session_id: String,
        title: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.rename_session(&session_id, title.trim()).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn read_file(
        path: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.read_file(&path).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn request_generated_image(
        path: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.request_generated_image(&path).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn request_rollout_attachment(
        attachment_id: String,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.request_rollout_attachment(&attachment_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn request_audio(
        audio_id: String,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client.request_audio(&audio_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn audio_get(
        audio_id: String,
        app_id: String,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client.audio_get(&audio_id, &app_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn audio_register(
        request: serde_json::Value,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client.audio_register(request).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn audio_attach_transcript(
        audio_id: String,
        transcript: serde_json::Value,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client
            .audio_attach_transcript(&audio_id, transcript)
            .await
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn audio_list(
        filter: serde_json::Value,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client.audio_list(filter).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn audio_delete(
        audio_id: String,
        app_id: String,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client.audio_delete(&audio_id, &app_id).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn transcribe_audio(
        audio_base64: String,
        mime_type: String,
        language: Option<String>,
        state: State<'_, AppState>,
    ) -> Result<String, String> {
        let client = state.daemon.lock().await;
        client
            .transcribe_audio(&audio_base64, &mime_type, language.as_deref())
            .await
            .map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn request_rate_limits(
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.request_rate_limits().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn request_clawjs_service_statuses(
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        let client = state.daemon.lock().await;
        client.request_clawjs_service_statuses().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn start_pairing(state: State<'_, AppState>) -> Result<daemon_client::PairingPayload, String> {
        let client = state.daemon.lock().await;
        client.start_pairing().await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn list_audio_inputs() -> Result<Vec<dictation::AudioInput>, String> {
        dictation::list_inputs().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn start_dictation(
        device: Option<String>,
        app_handle: tauri::AppHandle,
    ) -> Result<String, String> {
        dictation::start(&app_handle, device).await.map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn stop_dictation() -> Result<(), String> {
        dictation::stop().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn inject_text(text: String) -> Result<(), String> {
        text_injector::inject(&text).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn read_primary_selection() -> Result<String, String> {
        selection_sniffer::read_primary().map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn open_quickask(app_handle: tauri::AppHandle) -> Result<(), String> {
        crate::shortcuts::open_quickask(&app_handle).map_err(|e| e.to_string())
    }

    #[derive(Serialize)]
    pub struct DaemonStatus {
        pub installed: bool,
        pub running: bool,
        pub version: Option<String>,
    }

    #[tauri::command]
    pub async fn daemon_status() -> Result<DaemonStatus, String> {
        let installed = service_manager::is_installed();
        let running = service_manager::is_active();
        let version = service_manager::daemon_version();
        Ok(DaemonStatus { installed, running, version })
    }

    #[tauri::command]
    pub async fn set_setting(
        key: String,
        value: serde_json::Value,
        state: State<'_, AppState>,
    ) -> Result<(), String> {
        state.db.set_setting(&key, &value.to_string()).map_err(|e| e.to_string())
    }

    #[tauri::command]
    pub async fn get_setting(
        key: String,
        state: State<'_, AppState>,
    ) -> Result<Option<String>, String> {
        state.db.get_setting(&key).map_err(|e| e.to_string())
    }
}
