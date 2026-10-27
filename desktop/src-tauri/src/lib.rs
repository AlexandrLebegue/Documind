use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

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

#[derive(Deserialize)]
struct AgentStateFile {
    status: AgentStatusFile,
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

fn read_server(app: tauri::AppHandle) -> Result<Option<String>, String> {
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

fn write_server(app: tauri::AppHandle, server: String) -> Result<(), String> {
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

fn service_config_path() -> PathBuf {
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
    service_config_path()
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

fn command(program: impl AsRef<std::ffi::OsStr>) -> Command {
    let mut cmd = Command::new(program);
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    cmd
}

fn wait_command(cmd: &mut Command, timeout: Duration) -> Result<std::process::ExitStatus, String> {
    let mut child = cmd.spawn().map_err(|err| err.to_string())?;
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait().map_err(|err| err.to_string())? {
            return Ok(status);
        }
        if start.elapsed() >= timeout {
            let _ = child.kill();
            let _ = child.wait();
            return Err("Délai de la commande système dépassé".into());
        }
        std::thread::sleep(Duration::from_millis(25));
    }
}

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tokio::time::timeout(Duration::from_secs(125), tokio::task::spawn_blocking(work))
        .await
        .map_err(|_| "Délai de l'opération dépassé".to_string())?
        .map_err(|err| err.to_string())?
}

fn run_agent(args: &[&str], elevated: bool) -> Result<(), String> {
    let binary = agent_binary_path()?;
    #[cfg(windows)]
    if elevated {
        // Quote each argument for the Windows command line, then for PowerShell.
        let arguments = args
            .iter()
            .map(|arg| format!("\"{}\"", arg.replace('"', "\\\"")))
            .collect::<Vec<_>>()
            .join(" ");
        let script = format!(
            "$ErrorActionPreference = 'Stop'; $p = Start-Process -FilePath '{}' -ArgumentList '{}' -Verb RunAs -WindowStyle Hidden -PassThru; if (!$p.WaitForExit(110000)) {{ Stop-Process -Id $p.Id -Force; exit 124 }}; exit $p.ExitCode",
            binary.to_string_lossy().replace('\'', "''"), arguments.replace('\'', "''")
        );
        let status = wait_command(
            command("powershell.exe").args(["-NoProfile", "-NonInteractive", "-Command", &script]),
            Duration::from_secs(120),
        )?;
        return if status.success() {
            Ok(())
        } else {
            Err(format!("Commande élevée échouée ({status})"))
        };
    }
    let _ = elevated;
    let status = wait_command(command(&binary).args(args), Duration::from_secs(120))?;
    if !status.success() {
        return Err(format!("documind-agent {:?} a échoué ({status})", args));
    }
    Ok(())
}

fn service_installed() -> Result<bool, String> {
    #[cfg(windows)]
    {
        let status = wait_command(
            command("sc.exe").args(["query", AGENT_SERVICE]),
            Duration::from_secs(3),
        )?;
        match status.code() {
            Some(0) => Ok(true),
            Some(1060) => Ok(false),
            _ => Err(format!("sc query a échoué ({status})")),
        }
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
                return Ok(true);
            }
        }
        Ok(wait_command(
            command("systemctl").args(["--user", "is-enabled", "documind-agent"]),
            Duration::from_secs(3),
        )?
        .success())
    }
    #[cfg(not(any(windows, target_os = "linux")))]
    {
        Ok(false)
    }
}

fn read_agent_status() -> AgentStatusFile {
    let path = agent_status_path();
    if !path.exists() {
        return AgentStatusFile::default();
    }
    fs::read_to_string(path)
        .ok()
        .and_then(|raw| serde_json::from_str::<AgentStateFile>(&raw).ok())
        .map(|state| state.status)
        .unwrap_or_default()
}

fn user_config_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app_config_dir(app)?.join("agent.json"))
}

fn read_config(path: &Path) -> Result<AgentConfig, String> {
    match fs::read(path) {
        Ok(raw) => serde_json::from_slice(&raw)
            .map_err(|err| format!("Configuration {} invalide : {err}", path.display())),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(AgentConfig::default()),
        Err(err) => Err(format!("Lecture {} : {err}", path.display())),
    }
}

fn write_config(path: &Path, config: &AgentConfig) -> Result<(), String> {
    use std::io::Write;
    let parent = path.parent().ok_or("Dossier de configuration absent")?;
    fs::create_dir_all(parent).map_err(|err| err.to_string())?;
    let mut temp = tempfile::NamedTempFile::new_in(parent).map_err(|err| err.to_string())?;
    temp.write_all(&serde_json::to_vec_pretty(config).map_err(|err| err.to_string())?)
        .map_err(|err| err.to_string())?;
    temp.as_file().sync_all().map_err(|err| err.to_string())?;
    temp.persist(path)
        .map_err(|err| format!("Enregistrement {} : {err}", path.display()))?;
    Ok(())
}

#[tauri::command]
async fn get_server(app: tauri::AppHandle) -> Result<Option<String>, String> {
    blocking(move || read_server(app)).await
}

#[tauri::command]
async fn set_server(app: tauri::AppHandle, server: String) -> Result<(), String> {
    blocking(move || write_server(app, server)).await
}

#[tauri::command]
async fn agent_get_config(app: tauri::AppHandle) -> Result<AgentConfig, String> {
    blocking(move || {
        let path = user_config_path(&app)?;
        let legacy = service_config_path();
        let mut config = read_config(if path.exists() { &path } else { &legacy })?;
        if config.server.is_empty() {
            config.server = read_server(app)?.unwrap_or_default();
        }
        write_config(&path, &config)?;
        Ok(config)
    })
    .await
}

#[tauri::command]
async fn agent_set_config(app: tauri::AppHandle, mut config: AgentConfig) -> Result<(), String> {
    blocking(move || {
        let path = user_config_path(&app)?;
        if config.server.is_empty() {
            config.server = read_server(app)?.unwrap_or_default();
        }
        write_config(&path, &config)
    })
    .await
}

#[tauri::command]
async fn agent_status(app: tauri::AppHandle) -> Result<AgentStatus, String> {
    blocking(move || {
        let state = read_agent_status();
        Ok(AgentStatus {
            installed: service_installed()?,
            running: state.running,
            last_run: state.last_run,
            counters: state.counters,
            last_error: state.last_error,
            config_path: user_config_path(&app)?.to_string_lossy().to_string(),
        })
    })
    .await
}

#[tauri::command]
async fn agent_install(app: tauri::AppHandle) -> Result<(), String> {
    blocking(move || {
        let path = user_config_path(&app)?;
        run_agent(
            &["install", "--from", &path.to_string_lossy()],
            cfg!(windows),
        )
    })
    .await
}

#[tauri::command]
async fn agent_uninstall() -> Result<(), String> {
    blocking(|| run_agent(&["uninstall"], cfg!(windows))).await
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_roundtrip_windows_paths_and_replace() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("user").join("agent.json");
        let mut config = AgentConfig {
            folders: vec![
                r"C:\Users\Chef\Mes documents\été".into(),
                r"\\nas\équipe partagée\archives".into(),
                r"\\?\C:\long path\archive".into(),
            ],
            ..Default::default()
        };
        write_config(&path, &config).unwrap();
        assert_eq!(read_config(&path).unwrap().folders, config.folders);
        config.folders.remove(0);
        write_config(&path, &config).unwrap();
        assert_eq!(read_config(&path).unwrap().folders, config.folders);
    }

    #[test]
    fn corrupt_and_unwritable_config_are_errors() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("agent.json");
        assert!(read_config(&path).unwrap().folders.is_empty());
        fs::write(&path, "{").unwrap();
        assert!(read_config(&path).is_err());
        assert!(write_config(&path.join("agent.json"), &AgentConfig::default()).is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "{");
    }

    #[test]
    fn system_command_timeout_kills_child() {
        #[cfg(windows)]
        let mut cmd = {
            let mut cmd = command("powershell.exe");
            cmd.args([
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "Start-Sleep -Seconds 10",
            ]);
            cmd
        };
        #[cfg(not(windows))]
        let mut cmd = {
            let mut cmd = command("sleep");
            cmd.arg("10");
            cmd
        };
        let start = Instant::now();
        assert!(wait_command(&mut cmd, Duration::from_millis(100)).is_err());
        assert!(start.elapsed() < Duration::from_secs(3));
    }

    #[test]
    fn reads_agent_status_inside_persisted_state() {
        let state: AgentStateFile = serde_json::from_str(
            r#"{"cache":{},"status":{"running":true,"last_run":"2026-10-27T10:00:00Z","counters":{"sent":4,"accepted":2,"rejected":1,"ignored":7},"last_error":null}}"#,
        )
        .unwrap();
        assert!(state.status.running);
        assert_eq!(state.status.counters.sent, 4);
        assert_eq!(state.status.counters.accepted, 2);
        assert_eq!(state.status.counters.rejected, 1);
        assert_eq!(state.status.counters.ignored, 7);
        assert!(state.status.last_run.is_some());
    }
}
