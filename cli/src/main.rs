//! The agent-facing CLI. Every command is one HTTP call to the host (or a
//! loop of them for `wait`) and prints one JSON document, so an agent can
//! read the result without parsing prose. `get` is the exception: it
//! prints raw HTML for redirection into a file.

use std::io::Read;
use std::process::ExitCode;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use clap::{Parser, Subcommand};
use reqwest::StatusCode;
use reqwest::blocking::{Client, Response};
use serde_json::{Value, json};

/// A single long-poll stays under every harness's command timeout. The
/// host enforces the same cap; the CLI loops to honor a longer --timeout.
const MAX_POLL_SECONDS: u64 = 100;
const EXIT_TIMEOUT: u8 = 3;

#[derive(Parser)]
#[command(
    name = "artifacts",
    version,
    about = "Publish interactive pages and wait for what viewers submit"
)]
struct Cli {
    /// Host URL, e.g. https://artifacts.example (or ARTIFACTS_URL)
    #[arg(long, env = "ARTIFACTS_URL", global = true)]
    url: Option<String>,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Publish an HTML file as a new artifact, or as a new version with --id
    Publish {
        /// Path to the HTML file, or - for stdin
        file: String,
        /// Title (required for a new artifact)
        #[arg(long)]
        title: Option<String>,
        /// Publish a new version of this artifact instead of creating one
        #[arg(long)]
        id: Option<String>,
        /// Only publish if this is the current version (with --id)
        #[arg(long)]
        if_version: Option<u64>,
    },
    /// List artifacts, most recently updated first
    List,
    /// Show one artifact's metadata
    Show { id: String },
    /// List an artifact's versions
    Versions { id: String },
    /// Print an artifact's HTML (current version unless --version)
    Get {
        id: String,
        #[arg(long)]
        version: Option<u64>,
    },
    /// Read or write shared state
    #[command(subcommand)]
    State(StateCommand),
    /// Submit as the agent (a snapshot of state plus an optional payload)
    Submit {
        id: String,
        /// JSON payload
        #[arg(long)]
        payload: Option<String>,
    },
    /// List submissions, optionally after a cursor
    Submissions {
        id: String,
        #[arg(long, default_value_t = 0)]
        since: u64,
    },
    /// Block until a viewer submits, then print the submission
    Wait {
        id: String,
        /// Only return submissions after this cursor (a submission id)
        #[arg(long)]
        since: Option<u64>,
        /// Seconds to wait before exiting 3
        #[arg(long, default_value_t = 90)]
        timeout: u64,
    },
    /// Delete an artifact and everything under it
    Delete { id: String },
}

#[derive(Subcommand)]
enum StateCommand {
    /// Print the state object, or the subtree at a path
    Get { id: String, path: Option<String> },
    /// Set a path to a JSON value (null deletes)
    Set {
        id: String,
        path: String,
        value: String,
    },
    /// Delete a path and everything below it
    Delete { id: String, path: String },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    let url = match cli.url {
        Some(url) => url.trim_end_matches('/').to_string(),
        None => {
            eprintln!("{}", json!({"error": "set ARTIFACTS_URL or pass --url"}));
            return ExitCode::from(1);
        }
    };
    let host = Host::new(url);

    match run(&host, cli.command) {
        Ok(Outcome::Printed) => ExitCode::SUCCESS,
        Ok(Outcome::Timeout) => ExitCode::from(EXIT_TIMEOUT),
        Err(err) => {
            eprintln!("{}", json!({"error": err.to_string()}));
            ExitCode::from(1)
        }
    }
}

enum Outcome {
    Printed,
    Timeout,
}

fn run(host: &Host, command: Command) -> Result<Outcome> {
    match command {
        Command::Publish {
            file,
            title,
            id,
            if_version,
        } => {
            let html = read_input(&file)?;
            let body = match &id {
                Some(id) => {
                    let mut body = json!({"html": html});
                    if let Some(title) = title {
                        body["title"] = json!(title);
                    }
                    if let Some(v) = if_version {
                        body["if_version"] = json!(v);
                    }
                    host.put(&format!("/api/artifacts/{id}"), &body)?
                }
                None => {
                    let title =
                        title.ok_or_else(|| anyhow!("--title is required for a new artifact"))?;
                    host.post("/api/artifacts", &json!({"title": title, "html": html}))?
                }
            };
            print(&body)
        }
        Command::List => print(&host.get("/api/artifacts")?),
        Command::Show { id } => print(&host.get(&format!("/api/artifacts/{id}"))?),
        Command::Versions { id } => print(&host.get(&format!("/api/artifacts/{id}/versions"))?),
        Command::Get { id, version } => {
            let number = version.map_or("current".to_string(), |n| n.to_string());
            let body = host.get(&format!("/api/artifacts/{id}/versions/{number}"))?;
            let html = body["html"]
                .as_str()
                .ok_or_else(|| anyhow!("host returned no html"))?;
            print!("{html}");
            Ok(Outcome::Printed)
        }
        Command::State(StateCommand::Get { id, path }) => {
            let query = path
                .map(|p| format!("?path={}", urlencode(&p)))
                .unwrap_or_default();
            print(&host.get(&format!("/api/artifacts/{id}/state{query}"))?)
        }
        Command::State(StateCommand::Set { id, path, value }) => {
            let value: Value = serde_json::from_str(&value).context("value must be JSON")?;
            let ops = json!([{"op": "set", "path": path, "value": value}]);
            print(&host.post(&format!("/api/artifacts/{id}/state"), &json!({"ops": ops}))?)
        }
        Command::State(StateCommand::Delete { id, path }) => {
            let ops = json!([{"op": "delete", "path": path}]);
            print(&host.post(&format!("/api/artifacts/{id}/state"), &json!({"ops": ops}))?)
        }
        Command::Submit { id, payload } => {
            let payload = match payload {
                Some(raw) => serde_json::from_str::<Value>(&raw).context("payload must be JSON")?,
                None => Value::Null,
            };
            print(&host.post(
                &format!("/api/artifacts/{id}/submissions"),
                &json!({"payload": payload}),
            )?)
        }
        Command::Submissions { id, since } => {
            print(&host.get(&format!("/api/artifacts/{id}/submissions?since={since}"))?)
        }
        Command::Wait { id, since, timeout } => wait(host, &id, since, timeout),
        Command::Delete { id } => {
            host.delete(&format!("/api/artifacts/{id}"))?;
            print(&json!({"deleted": id}))
        }
    }
}

/// Without --since, only submissions made after the call started count:
/// the agent is asking "what does the viewer do next", not "what has
/// anyone ever submitted".
fn wait(host: &Host, id: &str, since: Option<u64>, timeout: u64) -> Result<Outcome> {
    let mut cursor = match since {
        Some(cursor) => cursor,
        None => {
            let existing = host.get(&format!("/api/artifacts/{id}/submissions"))?;
            existing
                .as_array()
                .and_then(|list| list.last())
                .and_then(|last| last["id"].as_u64())
                .unwrap_or(0)
        }
    };
    let deadline = Instant::now() + Duration::from_secs(timeout);

    loop {
        let remaining = deadline.saturating_duration_since(Instant::now()).as_secs();
        let poll = remaining.min(MAX_POLL_SECONDS);
        let path = format!("/api/artifacts/{id}/submissions?since={cursor}&timeout={poll}");
        let response = host.request(host.client.get(host.url(&path)))?;

        if response.status() == StatusCode::NO_CONTENT {
            if remaining == 0 || Instant::now() >= deadline {
                return Ok(Outcome::Timeout);
            }
            continue;
        }

        let body: Value = response.json().context("host returned invalid JSON")?;
        let list = body
            .as_array()
            .ok_or_else(|| anyhow!("host returned a non-list"))?;
        match list.first() {
            Some(first) => return print(first),
            None => {
                if let Some(last) = list.last().and_then(|s| s["id"].as_u64()) {
                    cursor = last;
                }
            }
        }
    }
}

struct Host {
    base: String,
    client: Client,
}

impl Host {
    fn new(base: String) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(MAX_POLL_SECONDS + 15))
            .build()
            .expect("HTTP client");
        Host { base, client }
    }

    fn url(&self, path: &str) -> String {
        format!("{}{}", self.base, path)
    }

    fn get(&self, path: &str) -> Result<Value> {
        self.json(self.client.get(self.url(path)))
    }

    fn post(&self, path: &str, body: &Value) -> Result<Value> {
        self.json(self.client.post(self.url(path)).json(body))
    }

    fn put(&self, path: &str, body: &Value) -> Result<Value> {
        self.json(self.client.put(self.url(path)).json(body))
    }

    fn delete(&self, path: &str) -> Result<()> {
        self.request(self.client.delete(self.url(path))).map(|_| ())
    }

    fn json(&self, request: reqwest::blocking::RequestBuilder) -> Result<Value> {
        let response = self.request(request)?;
        if response.status() == StatusCode::NO_CONTENT {
            return Ok(Value::Null);
        }
        response.json().context("host returned invalid JSON")
    }

    fn request(&self, request: reqwest::blocking::RequestBuilder) -> Result<Response> {
        let response = request
            .send()
            .with_context(|| format!("could not reach {}", self.base))?;
        let status = response.status();
        if status.is_success() {
            return Ok(response);
        }
        let text = response.text().unwrap_or_default();
        let message = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v["error"].as_str().map(str::to_string))
            .unwrap_or_else(|| {
                if text.is_empty() {
                    status.to_string()
                } else {
                    text
                }
            });
        bail!("{message}")
    }
}

fn read_input(file: &str) -> Result<String> {
    if file == "-" {
        let mut html = String::new();
        std::io::stdin()
            .read_to_string(&mut html)
            .context("could not read stdin")?;
        Ok(html)
    } else {
        std::fs::read_to_string(file).with_context(|| format!("could not read {file}"))
    }
}

fn print(value: &Value) -> Result<Outcome> {
    println!("{}", serde_json::to_string_pretty(value)?);
    Ok(Outcome::Printed)
}

fn urlencode(raw: &str) -> String {
    raw.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::urlencode;

    #[test]
    fn state_paths_survive_the_query_string() {
        assert_eq!(urlencode("cards.c1.column"), "cards.c1.column");
        assert_eq!(urlencode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9");
    }
}
