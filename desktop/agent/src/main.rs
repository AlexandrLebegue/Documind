//! DocuMind folder synchronisation agent.
//!
//! Scans configured folders, filters files locally (extension + magic bytes,
//! hidden/temp/unstable/too small/too large), hashes them with SHA-256, asks
//! the server which hashes are unknown, and uploads only those candidates.
//! Runs as a Windows service (auto-start) or a systemd --user unit on Linux.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

fn system_output(cmd: &mut Command) -> Result<Output, std::io::Error> {
    use wait_timeout::ChildExt;
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x08000000);
    }
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    if child
        .wait_timeout(std::time::Duration::from_secs(10))?
        .is_none()
    {
        let _ = child.kill();
        let _ = child.wait();
        return Err(std::io::Error::new(
            std::io::ErrorKind::TimedOut,
            "Délai de la commande système dépassé",
        ));
    }
    child.wait_with_output()
}

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, UNIX_EPOCH};

use chrono::Local;
use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

#[cfg_attr(not(windows), allow(dead_code))]
const SERVICE_NAME: &str = "DocuMindAgent";
const ALLOWED_EXTENSIONS: &[&str] = &[".pdf", ".txt", ".jpg", ".jpeg", ".png", ".bmp"];
const MIN_SIZE: u64 = 1024;
const MAX_SIZE: u64 = 50 * 1024 * 1024;
const LOG_MAX_BYTES: u64 = 2 * 1024 * 1024;

// ---------------------------------------------------------------------------
// Configuration / state
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
struct Config {
    server: String,
    folders: Vec<String>,
    interval_minutes: u64,
    enabled: bool,
    machine: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            server: String::new(),
            folders: Vec::new(),
            interval_minutes: 60,
            enabled: false,
            machine: hostname(),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, Default, PartialEq, Eq)]
struct StatEntry {
    size: u64,
    mtime: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CacheEntry {
    size: u64,
    mtime: u64,
    sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
struct Counters {
    seen: u64,
    errors: u64,
    sent: u64,
    accepted: u64,
    rejected: u64,
    ignored: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(default)]
struct StatusFile {
    running: bool,
    last_run: Option<String>,
    next_run: Option<String>,
    phase: String,
    counters: Counters,
    last_error: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Default)]
#[serde(default)]
struct AgentState {
    cache: HashMap<String, CacheEntry>,
    stability: HashMap<String, StatEntry>,
    sent: HashMap<String, String>,
    counted: HashMap<String, String>,
    ignored_seen: HashSet<String>,
    status: StatusFile,
}

fn config_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("DOCUMIND_AGENT_DATA_DIR") {
        return PathBuf::from(dir);
    }
    #[cfg(windows)]
    {
        let base = std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".into());
        PathBuf::from(base).join("DocuMind")
    }
    #[cfg(not(windows))]
    {
        dirs::config_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join("documind")
    }
}

fn config_path() -> PathBuf {
    config_dir().join("agent.json")
}

fn state_path() -> PathBuf {
    config_dir().join("state.json")
}

fn log_path() -> PathBuf {
    config_dir().join("logs").join("agent.log")
}

fn hostname() -> String {
    std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "pc".into())
}

fn read_config(path: &Path) -> Result<Config, String> {
    let raw = fs::read(path).map_err(|err| format!("Configuration {} : {err}", path.display()))?;
    let mut config: Config = serde_json::from_slice(&raw)
        .map_err(|err| format!("Configuration {} invalide : {err}", path.display()))?;
    if normalize_server(&config.server).is_empty() {
        return Err("Adresse serveur vide".into());
    }
    if config.machine.is_empty() {
        config.machine = hostname();
    }
    config.interval_minutes = config.interval_minutes.max(1);
    Ok(config)
}

fn load_config() -> Result<Config, String> {
    read_config(&config_path())
}

fn save_config(config: &Config) -> Result<(), String> {
    fs::create_dir_all(config_dir()).map_err(|err| err.to_string())?;
    write_json(&config_path(), config)
}

fn load_state() -> AgentState {
    fs::read_to_string(state_path())
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

fn save_state(state: &AgentState) -> Result<(), String> {
    fs::create_dir_all(config_dir()).map_err(|err| err.to_string())?;
    write_json(&state_path(), state)
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), String> {
    let tmp = path.with_extension("tmp");
    let payload = serde_json::to_vec_pretty(value).map_err(|err| err.to_string())?;
    fs::write(&tmp, payload).map_err(|err| err.to_string())?;
    fs::rename(&tmp, path).map_err(|err| err.to_string())
}

fn now_iso() -> String {
    Local::now().to_rfc3339()
}

fn log(level: &str, message: &str) {
    let line = format!(
        "{} [{}] {}\n",
        Local::now().format("%Y-%m-%d %H:%M:%S"),
        level,
        message
    );
    eprint!("{}", line);
    let path = log_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(meta) = fs::metadata(&path) {
        if meta.len() > LOG_MAX_BYTES {
            let rotated = path.with_extension("log.1");
            let _ = fs::remove_file(&rotated);
            let _ = fs::rename(&path, &rotated);
        }
    }
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = file.write_all(line.as_bytes());
    }
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

fn file_stat(path: &Path) -> Option<StatEntry> {
    let meta = fs::metadata(path).ok()?;
    let mtime = meta
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0);
    Some(StatEntry {
        size: meta.len(),
        mtime,
    })
}

fn is_hidden(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| name.starts_with('.'))
        .unwrap_or(false)
        || path.components().any(|component| {
            component
                .as_os_str()
                .to_str()
                .map(|part| part.starts_with('.') && part != "." && part != "..")
                .unwrap_or(false)
        })
}

fn is_temporary(name: &str) -> bool {
    let lower = name.to_lowercase();
    name.starts_with("~$") || lower.ends_with(".tmp") || lower.ends_with(".part")
}

fn check_magic(path: &Path, ext: &str) -> Result<(), String> {
    let mut file = fs::File::open(path).map_err(|err| err.to_string())?;
    if ext == ".txt" {
        let mut data = Vec::new();
        file.take(MAX_SIZE + 1)
            .read_to_end(&mut data)
            .map_err(|err| err.to_string())?;
        if data.contains(&0) {
            return Err("octets nuls".into());
        }
        let text = String::from_utf8_lossy(&data);
        if text.trim().is_empty() {
            return Err("texte vide".into());
        }
        let control = text
            .chars()
            .filter(|ch| (*ch as u32) < 32 && !matches!(ch, '\n' | '\r' | '\t'))
            .count();
        if control > 8.max(text.len() / 20) {
            return Err("contenu binaire".into());
        }
        return Ok(());
    }

    let mut head = [0u8; 16];
    let read = file.read(&mut head).map_err(|err| err.to_string())?;
    let head = &head[..read];
    let ok = match ext {
        ".pdf" => head.starts_with(b"%PDF"),
        ".png" => head.starts_with(b"\x89PNG\r\n\x1a\n"),
        ".jpg" | ".jpeg" => head.starts_with(b"\xff\xd8\xff"),
        ".bmp" => head.starts_with(b"BM"),
        _ => false,
    };
    if ok {
        Ok(())
    } else {
        Err(format!("signature {ext} invalide"))
    }
}

fn hash_file(path: &Path) -> Result<String, String> {
    let mut file = fs::File::open(path).map_err(|err| err.to_string())?;
    let mut hasher = Sha256::new();
    // Windows main/SCM threads have a small default stack. A 1 MiB stack
    // array overflows before the first /check; keep the hash buffer on the heap.
    let mut buffer = vec![0u8; 1024 * 1024];
    loop {
        let read = file.read(&mut buffer).map_err(|err| err.to_string())?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(format!("{:x}", hasher.finalize()))
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
struct KnownMark {
    sha256: String,
    verdict: String,
}

#[derive(Debug, Deserialize)]
struct CheckResponse {
    known: Vec<KnownMark>,
    unknown: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct CandidateResponse {
    verdict: String,
}

fn normalize_server(value: &str) -> String {
    let trimmed = value.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        trimmed.to_string()
    } else {
        format!("http://{trimmed}")
    }
}

fn check_hashes(
    client: &reqwest::blocking::Client,
    server: &str,
    hashes: &[String],
) -> Result<CheckResponse, String> {
    let response = client
        .post(format!("{server}/api/ingest/check"))
        .json(&serde_json::json!({ "sha256": hashes }))
        .send()
        .map_err(|err| format!("Requête réseau : {err:?}"))?;
    if !response.status().is_success() {
        return Err(format!("check HTTP {}", response.status()));
    }
    response
        .json::<CheckResponse>()
        .map_err(|err| err.to_string())
}

fn upload_candidate(
    client: &reqwest::blocking::Client,
    server: &str,
    path: &Path,
    machine: &str,
) -> Result<CandidateResponse, String> {
    let form = reqwest::blocking::multipart::Form::new()
        .text("origin_path", path.to_string_lossy().to_string())
        .text("machine", machine.to_string())
        .text("force", "false")
        .file("file", path)
        .map_err(|err| err.to_string())?;
    let response = client
        .post(format!("{server}/api/ingest/candidate"))
        .multipart(form)
        .send()
        .map_err(|err| format!("Requête réseau : {err:?}"))?;
    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().unwrap_or_default();
        return Err(format!(
            "candidate HTTP {status}: {}",
            body.chars().take(300).collect::<String>()
        ));
    }
    response
        .json::<CandidateResponse>()
        .map_err(|err| err.to_string())
}

// ---------------------------------------------------------------------------
// Scan
// ---------------------------------------------------------------------------

fn mark_ignored(state: &mut AgentState, path: &Path, reason: &str) {
    let key = path.to_string_lossy().to_string();
    state.status.counters.ignored += 1;
    if state.ignored_seen.insert(key) {
        log("IGNORE", &format!("{} — {}", path.display(), reason));
    }
}

fn scan_once(config: &Config, state: &mut AgentState) -> Result<(), String> {
    let server = normalize_server(&config.server);
    if server.is_empty() {
        return Err("adresse serveur vide".into());
    }
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(180))
        .connect_timeout(Duration::from_secs(10))
        .default_headers({
            let mut headers = reqwest::header::HeaderMap::new();
            headers.insert(
                "x-documind-machine",
                config
                    .machine
                    .parse()
                    .map_err(|err| format!("Nom machine invalide : {err}"))?,
            );
            headers
        })
        .build()
        .map_err(|err| err.to_string())?;
    // An empty check is a lightweight heartbeat, even when every file is filtered.
    check_hashes(&client, &server, &[])
        .map_err(|err| format!("Serveur {server}, heartbeat/check impossible : {err}"))?;
    if config.folders.is_empty() {
        return Err("Aucun dossier configuré".into());
    }
    state.status.phase = "Analyse des dossiers".into();
    save_state(state)?;

    // 1. Refresh verdict counters for files already sent.
    if !state.sent.is_empty() {
        let hashes: Vec<String> = state.sent.keys().cloned().collect();
        match check_hashes(&client, &server, &hashes) {
            Ok(check) => {
                for mark in check.known {
                    let previous = state.counted.get(&mark.sha256).cloned();
                    if previous.as_deref() == Some(mark.verdict.as_str()) {
                        continue;
                    }
                    match mark.verdict.as_str() {
                        "accepted" => state.status.counters.accepted += 1,
                        "rejected" => state.status.counters.rejected += 1,
                        _ => {}
                    }
                    state.counted.insert(mark.sha256, mark.verdict);
                }
            }
            Err(err) => {
                state.status.counters.errors += 1;
                state.status.last_error = Some(format!("Check des verdicts impossible : {err}"));
                log("ERROR", state.status.last_error.as_deref().unwrap());
            }
        }
    }

    // 2. Walk folders and filter.
    let mut candidates: HashMap<String, PathBuf> = HashMap::new();
    for folder in &config.folders {
        let root = PathBuf::from(folder);
        if !root.exists() {
            state.status.counters.errors += 1;
            state.status.last_error = Some(format!("Dossier absent ou inaccessible : {} (service Windows : compte LocalSystem ; lecteurs réseau utilisateur indisponibles)", root.display()));
            log("ERROR", state.status.last_error.as_deref().unwrap());
            continue;
        }
        for item in WalkDir::new(&root).follow_links(false) {
            let entry = match item {
                Ok(entry) => entry,
                Err(err) => {
                    state.status.counters.errors += 1;
                    state.status.last_error = Some(format!("Accès dossier : {err}"));
                    log("ERROR", state.status.last_error.as_deref().unwrap());
                    continue;
                }
            };
            if !entry.file_type().is_file() {
                continue;
            }
            state.status.counters.seen += 1;
            if state.status.counters.seen.is_multiple_of(20) {
                state.status.phase =
                    format!("Analyse : {} fichiers vus", state.status.counters.seen);
                save_state(state)?;
            }
            let path = entry.path();
            if is_hidden(path) {
                mark_ignored(state, path, "fichier caché");
                continue;
            }
            let name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("");
            if is_temporary(name) {
                mark_ignored(state, path, "fichier temporaire");
                continue;
            }
            let ext = path
                .extension()
                .and_then(|value| value.to_str())
                .map(|value| format!(".{}", value.to_lowercase()))
                .unwrap_or_default();
            if !ALLOWED_EXTENSIONS.contains(&ext.as_str()) {
                mark_ignored(state, path, "extension non autorisée");
                continue;
            }
            let stat = match file_stat(path) {
                Some(stat) => stat,
                None => {
                    state.status.counters.errors += 1;
                    log(
                        "ERROR",
                        &format!("Métadonnées inaccessibles : {}", path.display()),
                    );
                    continue;
                }
            };
            if stat.size < MIN_SIZE || stat.size > MAX_SIZE {
                mark_ignored(state, path, "taille hors limites");
                continue;
            }
            let key = path.to_string_lossy().to_string();
            if state.stability.get(&key) != Some(&stat) {
                // Confirm stability within this run, so the first manual run can send files.
                std::thread::sleep(Duration::from_millis(250));
                if file_stat(path) != Some(stat) {
                    state.stability.insert(key, stat);
                    mark_ignored(state, path, "taille/mtime instables");
                    continue;
                }
                state.stability.insert(key.clone(), stat);
            }
            if let Err(reason) = check_magic(path, &ext) {
                mark_ignored(state, path, &reason);
                continue;
            }
            let sha = match state.cache.get(&key) {
                Some(entry) if entry.size == stat.size && entry.mtime == stat.mtime => {
                    entry.sha256.clone()
                }
                _ => match hash_file(path) {
                    Ok(sha) => {
                        state.cache.insert(
                            key.clone(),
                            CacheEntry {
                                size: stat.size,
                                mtime: stat.mtime,
                                sha256: sha.clone(),
                            },
                        );
                        sha
                    }
                    Err(err) => {
                        state.status.counters.errors += 1;
                        log(
                            "WARN",
                            &format!("hash impossible {}: {err}", path.display()),
                        );
                        continue;
                    }
                },
            };
            candidates.entry(sha).or_insert_with(|| path.to_path_buf());
        }
    }

    if candidates.is_empty() {
        log("INFO", "aucun fichier candidat stable");
        return Ok(());
    }

    // 3. Ask the server which hashes it has never seen.
    let hashes: Vec<String> = candidates.keys().cloned().collect();
    let check = check_hashes(&client, &server, &hashes)?;
    let unknown: HashSet<String> = check.unknown.into_iter().collect();
    log(
        "INFO",
        &format!(
            "{} candidat(s), {} inconnu(s) du serveur",
            candidates.len(),
            unknown.len()
        ),
    );

    // 4. Upload unknown files only.
    for (sha, path) in candidates {
        state.status.phase = format!(
            "Envoi : {} envoyés / {} fichiers vus",
            state.status.counters.sent, state.status.counters.seen
        );
        save_state(state)?;
        if !unknown.contains(&sha) {
            state.status.counters.ignored += 1;
            continue;
        }
        match upload_candidate(&client, &server, &path, &config.machine) {
            Ok(response) => {
                state.status.counters.sent += 1;
                if !state.sent.contains_key(&sha) {
                    state
                        .sent
                        .insert(sha.clone(), path.to_string_lossy().to_string());
                }
                if response.verdict == "accepted" {
                    state.status.counters.accepted += 1;
                    state.counted.insert(sha.clone(), "accepted".into());
                } else if response.verdict == "rejected" {
                    state.status.counters.rejected += 1;
                    state.counted.insert(sha.clone(), "rejected".into());
                }
                log(
                    "SEND",
                    &format!("{} ({sha}) -> {}", path.display(), response.verdict),
                );
            }
            Err(err) => {
                log(
                    "ERROR",
                    &format!("envoi impossible {}: {err}", path.display()),
                );
                return Err(err);
            }
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Run loop
// ---------------------------------------------------------------------------

fn sleep_with_stop(duration: Duration, stop: Option<&AtomicBool>) {
    let step = Duration::from_secs(1);
    let mut elapsed = Duration::ZERO;
    while elapsed < duration {
        if let Some(flag) = stop {
            if flag.load(Ordering::Relaxed) {
                return;
            }
        }
        std::thread::sleep(step);
        elapsed += step;
    }
}

fn run_cycle(config: &Config, state: &mut AgentState, automatic: bool) -> Result<(), String> {
    state.status.running = true;
    state.status.last_run = Some(now_iso());
    state.status.next_run = None;
    state.status.last_error = None;
    state.status.counters = Counters::default();
    state.status.phase = "Connexion au serveur".into();
    save_state(state)?;
    log(
        "INFO",
        &format!(
            "Passage : serveur={}, dossiers={}, automatique={automatic}",
            config.server,
            config.folders.len()
        ),
    );
    let result = scan_once(config, state);
    if let Err(err) = &result {
        state.status.counters.errors += 1;
        state.status.last_error = Some(err.clone());
        log("ERROR", err);
    }
    if state.status.counters.errors > 0 && state.status.last_error.is_none() {
        state.status.last_error = Some(format!(
            "{} erreur(s) pendant le passage ; consulter le journal",
            state.status.counters.errors
        ));
    }
    state.status.running = false;
    state.status.phase = if state.status.last_error.is_some() {
        "Terminé avec erreur"
    } else {
        "Terminé"
    }
    .into();
    if automatic && config.enabled {
        state.status.next_run = Some(
            (Local::now() + chrono::Duration::minutes(config.interval_minutes as i64)).to_rfc3339(),
        );
    }
    log("INFO", &format!("Résultat : {:?}", state.status.counters));
    save_state(state)?;
    result?;
    if let Some(err) = &state.status.last_error {
        return Err(err.clone());
    }
    Ok(())
}

fn run_loop(stop: Option<&AtomicBool>) {
    log(
        "INFO",
        &format!("agent démarré (config: {})", config_path().display()),
    );
    loop {
        if let Some(flag) = stop {
            if flag.load(Ordering::Relaxed) {
                break;
            }
        }
        let config = load_config();
        let mut state = load_state();
        let wait_minutes = match config {
            Ok(config) if config.enabled => {
                let _ = run_cycle(&config, &mut state, true);
                config.interval_minutes
            }
            Ok(_) => {
                state.status.running = false;
                state.status.next_run = None;
                state.status.phase = "Synchronisation automatique désactivée".into();
                let _ = save_state(&state);
                1
            }
            Err(err) => {
                state.status.last_error = Some(err.clone());
                state.status.running = false;
                log("ERROR", &err);
                let _ = save_state(&state);
                1
            }
        };
        sleep_with_stop(Duration::from_secs(wait_minutes * 60), stop);
    }
    let mut state = load_state();
    state.status.running = false;
    let _ = save_state(&state);
    log("INFO", "agent arrêté");
}

// ---------------------------------------------------------------------------
// Service installation
// ---------------------------------------------------------------------------

fn install_service() -> Result<(), String> {
    if !config_path().exists() {
        save_config(&Config::default())?;
    }
    #[cfg(windows)]
    {
        let exe = std::env::current_exe().map_err(|err| err.to_string())?;
        let bin_path = format!("\"{}\"", exe.display());
        let output = system_output(Command::new("sc").args([
            "create",
            SERVICE_NAME,
            "binPath=",
            &bin_path,
            "start=",
            "auto",
            "DisplayName=",
            "DocuMind Agent",
        ]))
        .map_err(|err| err.to_string())?;
        if !output.status.success() {
            let message = String::from_utf8_lossy(&output.stdout);
            if output.status.code() != Some(1073) {
                return Err(format!("sc create: {}", message.trim()));
            }
        }
        let output = system_output(Command::new("sc").args([
            "config",
            SERVICE_NAME,
            "binPath=",
            &bin_path,
            "start=",
            "auto",
        ]))
        .map_err(|err| err.to_string())?;
        if !output.status.success() {
            return Err(format!(
                "sc config : {}",
                String::from_utf8_lossy(&output.stdout)
            ));
        }
        let _ = system_output(Command::new("sc").args(["stop", SERVICE_NAME]));
        // Query SCM numerically: sc output is localised on French Windows.
        use windows_service::service::{ServiceAccess, ServiceState};
        use windows_service::service_manager::{ServiceManager, ServiceManagerAccess};
        let manager = ServiceManager::local_computer(None::<&str>, ServiceManagerAccess::CONNECT)
            .map_err(|err| format!("SCM : {err}"))?;
        let service = manager
            .open_service(SERVICE_NAME, ServiceAccess::QUERY_STATUS)
            .map_err(|err| format!("Service : {err}"))?;
        let deadline = std::time::Instant::now() + Duration::from_secs(60);
        while service
            .query_status()
            .map_err(|err| err.to_string())?
            .current_state
            != ServiceState::Stopped
        {
            if std::time::Instant::now() >= deadline {
                return Err("Le service ne s’arrête pas ; configuration copiée mais redémarrage non effectué".into());
            }
            std::thread::sleep(Duration::from_millis(250));
        }
        let output = system_output(Command::new("sc").args(["start", SERVICE_NAME]))
            .map_err(|err| err.to_string())?;
        if !output.status.success() && output.status.code() != Some(1056) {
            return Err(format!(
                "sc start: {}",
                String::from_utf8_lossy(&output.stdout)
            ));
        }
        log("INFO", "service Windows installé");
    }
    #[cfg(target_os = "linux")]
    {
        use std::os::unix::fs::PermissionsExt;

        let exe = std::env::current_exe().map_err(|err| err.to_string())?;
        let home = dirs::home_dir().ok_or("home introuvable")?;
        // AppImage extracts the sidecar to a temporary mount: keep a stable copy.
        let bin_dir = home.join(".local").join("bin");
        fs::create_dir_all(&bin_dir).map_err(|err| err.to_string())?;
        let bin = bin_dir.join("documind-agent");
        if exe != bin {
            fs::copy(&exe, &bin).map_err(|err| err.to_string())?;
            let mut perms = fs::metadata(&bin)
                .map_err(|err| err.to_string())?
                .permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&bin, perms).map_err(|err| err.to_string())?;
        }
        let unit_dir = home.join(".config").join("systemd").join("user");
        fs::create_dir_all(&unit_dir).map_err(|err| err.to_string())?;
        let unit = format!(
            "[Unit]\nDescription=DocuMind folder sync agent\nAfter=network-online.target\n\n\
             [Service]\nType=simple\nExecStart=\"{}\" run\nRestart=on-failure\nRestartSec=30\n\n\
             [Install]\nWantedBy=default.target\n",
            bin.display()
        );
        fs::write(unit_dir.join("documind-agent.service"), unit).map_err(|err| err.to_string())?;
        let _ = system_output(Command::new("systemctl").args(["--user", "daemon-reload"]));
        let status = system_output(Command::new("systemctl").args([
            "--user",
            "enable",
            "--now",
            "documind-agent",
        ]))
        .map_err(|err| err.to_string())?;
        if !status.status.success() {
            return Err("systemctl --user enable --now a échoué".into());
        }
        let output =
            system_output(Command::new("systemctl").args(["--user", "restart", "documind-agent"]))
                .map_err(|err| err.to_string())?;
        if !output.status.success() {
            return Err("systemctl --user restart a échoué".into());
        }
        log("INFO", "service systemd --user installé");
    }
    Ok(())
}

fn uninstall_service() -> Result<(), String> {
    #[cfg(windows)]
    {
        let _ = system_output(Command::new("sc").args(["stop", SERVICE_NAME]));
        let output = system_output(Command::new("sc").args(["delete", SERVICE_NAME]))
            .map_err(|err| err.to_string())?;
        if !output.status.success() {
            let message = String::from_utf8_lossy(&output.stdout);
            if output.status.code() != Some(1060) {
                return Err(format!("sc delete: {}", message.trim()));
            }
        }
        log("INFO", "service Windows désinstallé");
    }
    #[cfg(target_os = "linux")]
    {
        let _ = system_output(Command::new("systemctl").args([
            "--user",
            "disable",
            "--now",
            "documind-agent",
        ]));
        if let Some(home) = dirs::home_dir() {
            let unit = home
                .join(".config")
                .join("systemd")
                .join("user")
                .join("documind-agent.service");
            let _ = fs::remove_file(unit);
        }
        let _ = system_output(Command::new("systemctl").args(["--user", "daemon-reload"]));
        log("INFO", "service systemd --user désinstallé");
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// Windows service runtime
// ---------------------------------------------------------------------------

#[cfg(windows)]
mod winservice {
    use super::*;
    use std::ffi::OsString;
    use std::sync::Arc;
    use windows_service::service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    };
    use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
    use windows_service::service_dispatcher;

    windows_service::define_windows_service!(ffi_service_main, service_main);

    pub fn try_run() -> bool {
        service_dispatcher::start(SERVICE_NAME, ffi_service_main).is_ok()
    }

    fn service_main(_arguments: Vec<OsString>) {
        let stop = Arc::new(AtomicBool::new(false));
        let handler_stop = stop.clone();
        let event_handler = move |control_event| -> ServiceControlHandlerResult {
            match control_event {
                ServiceControl::Stop => {
                    handler_stop.store(true, Ordering::Relaxed);
                    ServiceControlHandlerResult::NoError
                }
                ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
                _ => ServiceControlHandlerResult::NotImplemented,
            }
        };
        let status_handle = match service_control_handler::register(SERVICE_NAME, event_handler) {
            Ok(handle) => handle,
            Err(_) => return,
        };
        let running = ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(30),
            process_id: None,
        };
        let _ = status_handle.set_service_status(running);
        run_loop(Some(&stop));
        let stopped = ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::from_secs(0),
            process_id: None,
        };
        let _ = status_handle.set_service_status(stopped);
    }
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

#[derive(Parser)]
#[command(name = "documind-agent", about = "Agent de synchronisation DocuMind")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
    #[arg(long, global = true)]
    data_dir: Option<PathBuf>,
}

#[derive(Subcommand)]
enum Commands {
    /// Run the agent in the foreground.
    Run,
    /// Run a single scan and exit.
    Once {
        #[arg(long)]
        from: Option<PathBuf>,
    },
    /// Install the Windows service / systemd user unit.
    Install {
        #[arg(long)]
        from: Option<PathBuf>,
    },
    /// Uninstall the service.
    Uninstall,
    /// Copy a configuration file to the canonical path.
    Configure {
        #[arg(long)]
        from: PathBuf,
    },
    /// Print the current status as JSON.
    Status {
        #[arg(long)]
        json: bool,
    },
}

fn main() {
    #[cfg(windows)]
    {
        if std::env::args_os().len() == 1 && winservice::try_run() {
            return;
        }
    }

    let cli = Cli::parse();
    if let Some(dir) = cli.data_dir {
        std::env::set_var("DOCUMIND_AGENT_DATA_DIR", dir);
    }
    let result = match cli.command {
        None | Some(Commands::Run) => {
            run_loop(None);
            Ok(())
        }
        Some(Commands::Once { from }) => (|| {
            let config = read_config(&from.unwrap_or_else(config_path))?;
            let mut state = load_state();
            // Manual synchronisation is independent of the automatic enabled switch.
            run_cycle(&config, &mut state, false)
        })(),
        Some(Commands::Install { from }) => (|| {
            if let Some(path) = from {
                let raw = fs::read(path).map_err(|err| err.to_string())?;
                let config: Config = serde_json::from_slice(&raw).map_err(|err| err.to_string())?;
                save_config(&config)?;
            }
            install_service()
        })(),
        Some(Commands::Uninstall) => uninstall_service(),
        Some(Commands::Configure { from }) => (|| {
            let raw = fs::read_to_string(&from).map_err(|err| err.to_string())?;
            let config: Config = serde_json::from_str(&raw).map_err(|err| err.to_string())?;
            save_config(&config)
        })(),
        Some(Commands::Status { json }) => {
            let state = load_state();
            if json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&state.status).unwrap_or_else(|_| "{}".into())
                );
            } else {
                println!("running: {}", state.status.running);
                println!("last_run: {:?}", state.status.last_run);
                println!("counters: {:?}", state.status.counters);
            }
            Ok(())
        }
    };

    if let Err(err) = result {
        log("ERROR", &err);
        eprintln!("documind-agent: {err}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn excludes_hidden_and_temporary_paths() {
        assert!(is_hidden(Path::new("archive/.cache/invoice.pdf")));
        assert!(is_hidden(Path::new(".invoice.pdf")));
        assert!(!is_hidden(Path::new("archive/invoice.pdf")));
        for name in ["~$invoice.pdf", "invoice.TMP", "invoice.part"] {
            assert!(is_temporary(name));
        }
        assert!(!is_temporary("invoice.pdf"));
    }

    #[test]
    fn validates_signatures_and_text_before_upload() {
        let path = std::env::temp_dir().join(format!("documind-magic-{}", std::process::id()));
        for (ext, bytes) in [
            (".pdf", b"%PDF-1.7".as_slice()),
            (".png", b"\x89PNG\r\n\x1a\n".as_slice()),
            (".jpg", b"\xff\xd8\xff".as_slice()),
            (".jpeg", b"\xff\xd8\xff".as_slice()),
            (".bmp", b"BM".as_slice()),
            (".txt", b"Facture caf\xe9".as_slice()),
        ] {
            fs::write(&path, bytes).unwrap();
            assert!(check_magic(&path, ext).is_ok(), "{ext}");
        }
        for (ext, bytes) in [
            (".pdf", b"PK archive".as_slice()),
            (".png", b"not an image".as_slice()),
            (".txt", b"binary\0data".as_slice()),
            (".txt", b"  \n".as_slice()),
            (".exe", b"MZ".as_slice()),
        ] {
            fs::write(&path, bytes).unwrap();
            assert!(check_magic(&path, ext).is_err(), "{ext}");
        }
        fs::remove_file(path).unwrap();
    }
}
