use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::{Deserialize, Serialize};
use tauri::Manager;

#[cfg(windows)]
const AGENT_SERVICE: &str = "DocuMindAgent";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
struct AgentConfig {
    server: String,
    folders: Vec<String>,
    interval_minutes: u64,
    enabled: bool,
    machine: String,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            server: String::new(),
            folders: Vec::new(),
            interval_minutes: 60,
            enabled: false,
            machine: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
struct Counters {
    sent: u64,
    accepted: u64,
    rejected: u64,
    ignored: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
struct AgentStatusFile {
    running: bool,
    last_run: Option<String>,
    counters: Counters,
    last_error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct AgentStatus {
    installed: bool,
    running: bool,
    last_run: Option<String>,
    counters: Counters,
    last_error: Option<String>,
    config_path: String,
}

fn app_config_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app
        .path()
        .app_config_dir()
        .map_err(|err| format!("app config dir unavailable: {err}"))?;
    fs::create_dir_all(&dir).map_err(|err| err.to_string())?;
    Ok(dir)
}

#[tauri::command]
fn get_server(app: tauri::AppHandle) -> Result<Option<String>, String> {
    let path = app_config_dir(&app)?.join("server.json");
    if !path.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(path).map_err(|err| err.to_string())?;
    let value: serde_json::Value = serde_json::from_str(&raw).map_err(|err| err.to_string())?;
    Ok(value
        .get("server")
        .and_then(|item| item.as_str())
        .map(|item| item.to_string()))
}

#[tauri::command]
fn set_server(app: tauri::AppHandle, server: String) -> Result<(), String> {
    let path = app_config_dir(&app)?.join("server.json");
    let payload = serde_json::json!({ "server": server });
    fs::write(
        path,
        serde_json::to_vec_pretty(&payload).map_err(|err| err.to_string())?,
    )
    .map_err(|err| err.to_string())
}

#[tauri::command]
async fn pick_folder() -> Result<Option<String>, String> {
    tauri::async_runtime::spawn_blocking(|| {
        rfd::FileDialog::new()
            .pick_folder()
            .map(|path| path.to_string_lossy().to_string())
    })
    .await
    .map_err(|err| err.to_string())
}

fn agent_config_path() -> PathBuf {
    #[cfg(windows)]
    {
        let base = std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".into());
        PathBuf::from(base).join("DocuMind").join("agent.json")
    }
    #[cfg(not(windows))]
    {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("documind")
            .join("agent.json")
    }
}

fn agent_status_path() -> PathBuf {
    agent_config_path()
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join("state.json")
}

fn agent_binary_path() -> Result<PathBuf, String> {
    if let Ok(value) = std::env::var("DOCUMIND_AGENT_BIN") {
        let path = PathBuf::from(value);
        if path.exists() {
            return Ok(path);
        }
    }

    let exe = std::env::current_exe().map_err(|err| err.to_string())?;
    if let Some(dir) = exe.parent() {
        for name in ["documind-agent.exe", "documind-agent"] {
            let candidate = dir.join(name);
            if candidate.exists() {
                return Ok(candidate);
            }
        }
    }

    // Development fallback: workspace target directory.
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for profile in ["release", "debug"] {
        let candidate = manifest
            .join("..")
            .join("target")
            .join(profile)
            .join(if cfg!(windows) {
                "documind-agent.exe"
            } else {
                "documind-agent"
            });
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    Err("documind-agent introuvable (lancez `cargo build -p documind-agent` ou utilisez l'installateur)".into())
}

fn run_agent(args: &[&str], elevated: bool) -> Result<(), String> {
    let binary = agent_binary_path()?;
    #[cfg(windows)]
    {
        if elevated {
            let argument_list = args
                .iter()
                .map(|arg| format!("'{}'", arg.replace('\'', "''")))
                .collect::<Vec<_>>()
                .join(",");
            let script = format!(
                "Start-Process -FilePath '{}' -ArgumentList @({}) -Verb RunAs -Wait",
                binary.to_string_lossy().replace('\'', "''"),
                argument_list
            );
            let status = Command::new("powershell")
                .args(["-NoProfile", "-NonInteractive", "-Command", &script])
                .status()
                .map_err(|err| err.to_string())?;
            if !status.success() {
                return Err(format!("commande élevée échouée ({status})"));
            }
            return Ok(());
        }
    }
    let _ = elevated;
    let status = Command::new(&binary)
        .args(args)
        .status()
        .map_err(|err| err.to_string())?;
    if !status.success() {
        return Err(format!("documind-agent {:?} a échoué ({status})", args));
    }
    Ok(())
}

fn service_installed() -> bool {
    #[cfg(windows)]
    {
        Command::new("sc")
            .args(["query", AGENT_SERVICE])
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    #[cfg(target_os = "linux")]
    {
        if let Some(home) = dirs::home_dir() {
            let unit = home
                .join(".config")
                .join("systemd")
                .join("user")
                .join("documind-agent.service");
            if unit.exists() {
                return true;
            }
        }
        Command::new("systemctl")
            .args(["--user", "is-enabled", "documind-agent"])
            .output()
            .map(|output| output.status.success())
            .unwrap_or(false)
    }
    #[cfg(not(any(windows, target_os = "linux")))]
    {
        false
    }
}

fn read_agent_status() -> AgentStatusFile {
    let path = agent_status_path();
    if !path.exists() {
        return AgentStatusFile::default();
    }
    fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

#[tauri::command]
fn agent_get_config(app: tauri::AppHandle) -> Result<AgentConfig, String> {
    let path = agent_config_path();
    let mut config = if path.exists() {
        fs::read_to_string(&path)
            .ok()
            .and_then(|raw| serde_json::from_str::<AgentConfig>(&raw).ok())
            .unwrap_or_default()
    } else {
        AgentConfig::default()
    };
    if config.server.is_empty() {
        config.server = get_server(app)?.unwrap_or_default();
    }
    Ok(config)
}

#[tauri::command]
fn agent_set_config(app: tauri::AppHandle, mut config: AgentConfig) -> Result<(), String> {
    if config.server.is_empty() {
        config.server = get_server(app)?.unwrap_or_default();
    }
    let path = agent_config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    }
    let payload = serde_json::to_vec_pretty(&config).map_err(|err| err.to_string())?;

    if fs::write(&path, &payload).is_ok() {
        return Ok(());
    }

    // On Windows ProgramData is protected: let the elevated agent copy it.
    let temp = std::env::temp_dir().join("documind-agent-config.json");
    fs::write(&temp, &payload).map_err(|err| err.to_string())?;
    run_agent(
        &["configure", "--from", &temp.to_string_lossy()],
        cfg!(windows),
    )
}

#[tauri::command]
fn agent_status() -> AgentStatus {
    let state = read_agent_status();
    AgentStatus {
        installed: service_installed(),
        running: state.running,
        last_run: state.last_run,
        counters: state.counters,
        last_error: state.last_error,
        config_path: agent_config_path().to_string_lossy().to_string(),
    }
}

#[tauri::command]
fn agent_install() -> Result<(), String> {
    run_agent(&["install"], cfg!(windows))
}

#[tauri::command]
fn agent_uninstall() -> Result<(), String> {
    run_agent(&["uninstall"], cfg!(windows))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_server,
            set_server,
            pick_folder,
            agent_get_config,
            agent_set_config,
            agent_status,
            agent_install,
            agent_uninstall
        ])
        .run(tauri::generate_context!())
        .expect("error while running DocuMind desktop");
}
