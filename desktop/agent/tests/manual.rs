use std::io::{Read, Write};
use std::net::TcpListener;
use std::process::Command;
use std::time::{Duration, Instant};

// Exercise the actual CLI, config selection, first-pass stability, HTTP and persisted result.
#[test]
fn manual_without_service_uses_current_config_even_when_automatic_is_disabled() {
    let dir = tempfile::Builder::new()
        .prefix("documind-test-")
        .tempdir()
        .unwrap();
    let docs = dir.path().join("Documents été");
    std::fs::create_dir(&docs).unwrap();
    std::fs::write(
        docs.join("document.txt"),
        "Document à archiver\n".repeat(100),
    )
    .unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    listener.set_nonblocking(true).unwrap();
    let server_url = format!("http://{}", listener.local_addr().unwrap());
    let server = std::thread::spawn(move || {
        let mut requests = Vec::new();
        let deadline = Instant::now() + Duration::from_secs(20);
        while requests.len() < 3 {
            let (mut stream, _) = match listener.accept() {
                Ok(connection) => connection,
                Err(err) if err.kind() == std::io::ErrorKind::WouldBlock => {
                    assert!(
                        Instant::now() < deadline,
                        "Agent did not send heartbeat/check/candidate"
                    );
                    std::thread::sleep(Duration::from_millis(10));
                    continue;
                }
                Err(err) => panic!("{err}"),
            };
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut raw = Vec::new();
            let header_end = loop {
                let mut byte = [0u8; 1];
                stream.read_exact(&mut byte).unwrap();
                raw.push(byte[0]);
                if raw.ends_with(b"\r\n\r\n") {
                    break raw.len();
                }
            };
            let header = String::from_utf8_lossy(&raw).to_lowercase();
            assert!(header.contains("x-documind-machine: chef-test"));
            let size: usize = header
                .lines()
                .find_map(|line| line.strip_prefix("content-length: "))
                .unwrap()
                .parse()
                .unwrap();
            raw.resize(header_end + size, 0);
            stream.read_exact(&mut raw[header_end..]).unwrap();
            let request = String::from_utf8_lossy(&raw).into_owned();
            let body = if header.starts_with("post /api/ingest/candidate ") {
                assert!(request.contains("Document à archiver"));
                r#"{"verdict":"accepted"}"#.to_string()
            } else {
                assert!(header.starts_with("post /api/ingest/check "));
                let payload: serde_json::Value =
                    serde_json::from_slice(&raw[header_end..]).unwrap();
                serde_json::json!({"known":[],"unknown":payload["sha256"]}).to_string()
            };
            write!(stream, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", body.len(), body).unwrap();
            requests.push(request);
        }
        requests
    });
    let config = dir.path().join("current.json");
    std::fs::write(
        &config,
        serde_json::to_vec(&serde_json::json!({
            "server": server_url, "folders": [docs], "enabled": false, "machine":"chef-test"
        }))
        .unwrap(),
    )
    .unwrap();
    let data = dir.path().join("manual");
    let output = Command::new(env!("CARGO_BIN_EXE_documind-agent"))
        .args(["once", "--from"])
        .arg(config)
        .arg("--data-dir")
        .arg(&data)
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    assert_eq!(server.join().unwrap().len(), 3);
    let state: serde_json::Value =
        serde_json::from_slice(&std::fs::read(data.join("state.json")).unwrap()).unwrap();
    assert_eq!(state["status"]["counters"]["seen"], 1);
    assert_eq!(state["status"]["counters"]["sent"], 1);
    assert_eq!(state["status"]["counters"]["accepted"], 1);
    assert_eq!(state["status"]["counters"]["errors"], 0);
    assert_eq!(state["status"]["running"], false);
    assert!(data.join("logs/agent.log").exists());
}

#[test]
fn network_failure_is_nonzero_logged_and_persisted() {
    let dir = tempfile::Builder::new()
        .prefix("documind-test-")
        .tempdir()
        .unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    drop(listener);
    let config = dir.path().join("current.json");
    std::fs::write(
        &config,
        serde_json::to_vec(&serde_json::json!({
            "server":url, "folders":[dir.path()], "enabled":true
        }))
        .unwrap(),
    )
    .unwrap();
    let data = dir.path().join("state");
    let output = Command::new(env!("CARGO_BIN_EXE_documind-agent"))
        .args(["once", "--from"])
        .arg(config)
        .arg("--data-dir")
        .arg(&data)
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stderr).contains("heartbeat/check impossible"));
    let state: serde_json::Value =
        serde_json::from_slice(&std::fs::read(data.join("state.json")).unwrap()).unwrap();
    assert_eq!(state["status"]["counters"]["errors"], 1);
    assert!(state["status"]["last_error"]
        .as_str()
        .unwrap()
        .contains("127.0.0.1"));
    assert_eq!(state["status"]["running"], false);
}
