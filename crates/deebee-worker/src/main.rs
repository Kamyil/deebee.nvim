use std::collections::HashMap;
use std::env;
use std::io::{self, BufRead, Write};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tokio::runtime::Runtime;
use tokio_postgres::{Client, NoTls, SimpleQueryMessage};

const WORKER_VERSION: &str = env!("CARGO_PKG_VERSION");
const PROTOCOL_VERSION: u32 = 1;

struct AppState {
    runtime: Runtime,
    sessions: HashMap<String, Session>,
    queries: HashMap<String, CachedQuery>,
    next_session_id: u64,
    next_query_id: u64,
}

struct Session {
    id: String,
    connection_id: String,
    name: String,
    adapter: String,
    client: Client,
}

struct CachedQuery {
    id: String,
    session_id: String,
    columns: Vec<String>,
    rows: Vec<Vec<Value>>,
    command_tag: Option<String>,
    page_size: usize,
}

#[derive(Debug, Deserialize)]
struct ConnectParams {
    connection: ConnectionDescriptor,
}

#[derive(Debug, Deserialize)]
struct ConnectionDescriptor {
    id: String,
    name: String,
    adapter: String,
    #[serde(default)]
    dsn: Option<String>,
    #[serde(default)]
    url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SessionRefParams {
    session_id: String,
}

#[derive(Debug, Deserialize)]
struct CatalogParams {
    session_id: String,
    node_kind: String,
    #[serde(default)]
    node_path: Vec<String>,
}

#[derive(Debug, Deserialize)]
struct RunQueryParams {
    session_id: String,
    sql: String,
    #[serde(default)]
    page_size: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct FetchPageParams {
    query_id: String,
    #[serde(default)]
    page_index: Option<usize>,
}

#[derive(Debug, Deserialize)]
struct Request {
    id: Value,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct SuccessResponse {
    id: Value,
    result: Value,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    id: Value,
    error: ErrorPayload,
}

#[derive(Debug, Serialize)]
struct ErrorPayload {
    code: &'static str,
    category: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<Value>,
    retryable: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    user_action: Option<String>,
}

fn main() -> Result<()> {
    let mut args = env::args().skip(1);

    match args.next().as_deref() {
        Some("--version") => {
            println!("{WORKER_VERSION}");
            Ok(())
        }
        Some("--stdio") => run_stdio(),
        Some(flag) => anyhow::bail!("unsupported flag: {flag}"),
        None => anyhow::bail!("expected --stdio or --version"),
    }
}

fn run_stdio() -> Result<()> {
    let stdin = io::stdin();
    let mut stdout = io::stdout().lock();
    let mut app = AppState::new()?;

    for line in stdin.lock().lines() {
        let line = line.context("failed to read stdio line")?;
        if line.trim().is_empty() {
            continue;
        }

        let request = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(error) => {
                let payload = ErrorResponse {
                    id: Value::Null,
                    error: ErrorPayload {
                        code: "invalid_request",
                        category: "protocol",
                        message: format!("failed to parse request: {error}"),
                        details: None,
                        retryable: false,
                        user_action: Some(
                            "Check the plugin and worker protocol implementation.".to_string(),
                        ),
                    },
                };
                write_json_line(&mut stdout, &payload)?;
                continue;
            }
        };

        match handle_request(&mut app, request) {
            Ok(response) => write_json_line(&mut stdout, &response)?,
            Err(response) => write_json_line(&mut stdout, &response)?,
        }
    }

    Ok(())
}

impl AppState {
    fn new() -> Result<Self> {
        Ok(Self {
            runtime: Runtime::new().context("failed to create Tokio runtime")?,
            sessions: HashMap::new(),
            queries: HashMap::new(),
            next_session_id: 1,
            next_query_id: 1,
        })
    }

    fn next_session_id(&mut self) -> String {
        let id = format!("session-{}", self.next_session_id);
        self.next_session_id += 1;
        id
    }

    fn next_query_id(&mut self) -> String {
        let id = format!("query-{}", self.next_query_id);
        self.next_query_id += 1;
        id
    }
}

fn handle_request(
    app: &mut AppState,
    request: Request,
) -> std::result::Result<SuccessResponse, ErrorResponse> {
    let request_id = request.id.clone();

    let result = match request.method.as_str() {
        "handshake" => {
            let plugin_version = request
                .params
                .get("plugin_version")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            let expected_worker_version = request
                .params
                .get("expected_worker_version")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            let requested_protocol_version = request
                .params
                .get("protocol_version")
                .and_then(Value::as_u64)
                .unwrap_or_default();

            if requested_protocol_version != u64::from(PROTOCOL_VERSION) {
                return Err(protocol_error(
                    request_id,
                    "protocol_mismatch",
                    format!(
                        "protocol mismatch: plugin requested {requested_protocol_version}, worker supports {PROTOCOL_VERSION}"
                    ),
                    Some("Update the plugin or worker so their protocol versions match.".to_string()),
                ));
            }

            if expected_worker_version != WORKER_VERSION {
                return Err(protocol_error(
                    request_id,
                    "worker_version_mismatch",
                    format!(
                        "worker version mismatch: plugin expects {expected_worker_version}, worker is {WORKER_VERSION}"
                    ),
                    Some("Reinstall the pinned worker version from the plugin.".to_string()),
                ));
            }

            json!({
                "worker_version": WORKER_VERSION,
                "protocol_version": PROTOCOL_VERSION,
                "capabilities": {
                    "install": true,
                    "health": true,
                    "querying": true,
                    "catalog": true,
                    "editable_grid": false
                },
                "adapters": {
                    "postgres": {
                        "available": true,
                        "reason": "postgres adapter is compiled in"
                    },
                    "oracle": {
                        "available": false,
                        "reason": "oracle adapter not implemented yet"
                    }
                },
                "platform": {
                    "os": env::consts::OS,
                    "arch": env::consts::ARCH
                },
                "plugin_version": plugin_version
            })
        }
        "health" => json!({
            "worker_version": WORKER_VERSION,
            "protocol_version": PROTOCOL_VERSION,
            "runtime": {
                "os": env::consts::OS,
                "arch": env::consts::ARCH
            },
            "sessions": app.sessions.len(),
            "queries": app.queries.len(),
            "session_summaries": app.sessions.values().map(|session| {
                json!({
                    "session_id": session.id,
                    "connection_id": session.connection_id,
                    "name": session.name,
                    "adapter": session.adapter,
                })
            }).collect::<Vec<_>>(),
            "adapters": {
                "postgres": {
                    "available": true,
                    "reason": "postgres adapter is compiled in"
                },
                "oracle": {
                    "available": false,
                    "reason": "oracle adapter not implemented yet"
                }
            }
        }),
        "connect" => connect(app, request_id, request.params)?,
        "disconnect" => disconnect(app, request_id, request.params)?,
        "ping_connection" => ping_connection(app, request_id, request.params)?,
        "list_catalog" => list_catalog(app, request_id, request.params)?,
        "run_query" => run_query(app, request_id, request.params)?,
        "fetch_page" => fetch_page(app, request_id, request.params)?,
        method => {
            return Err(ErrorResponse {
                id: request_id,
                error: ErrorPayload {
                    code: "method_not_found",
                    category: "protocol",
                    message: format!("unknown method: {method}"),
                    details: None,
                    retryable: false,
                    user_action: Some(
                        "Update the plugin or worker so they speak the same protocol.".to_string(),
                    ),
                },
            });
        }
    };

    Ok(SuccessResponse {
        id: request.id,
        result,
    })
}

fn connect(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: ConnectParams = decode_params(request_id.clone(), params)?;

    if params.connection.adapter != "postgres" {
        return Err(request_error(
            request_id,
            "unsupported_adapter",
            "unsupported",
            format!("adapter `{}` is not implemented yet", params.connection.adapter),
            Some("Use a PostgreSQL connection for now.".to_string()),
        ));
    }

    let dsn = params
        .connection
        .dsn
        .or(params.connection.url)
        .ok_or_else(|| {
            request_error(
                request_id.clone(),
                "missing_dsn",
                "validation",
                "connection is missing `dsn` or `url`".to_string(),
                Some("Provide a PostgreSQL connection string in the plugin config.".to_string()),
            )
        })?;

    let session_id = app.next_session_id();

    let (client, connection) = app.runtime.block_on(async {
        tokio_postgres::connect(&dsn, NoTls)
            .await
            .context("failed to connect to PostgreSQL")
    }).map_err(|error| {
        request_error(
            request_id.clone(),
            "connection_failed",
            "connection",
            error.to_string(),
            Some("Check the connection string and confirm PostgreSQL is reachable.".to_string()),
        )
    })?;

    app.runtime.spawn(async move {
        if let Err(error) = connection.await {
            eprintln!("deebee-worker connection error: {error}");
        }
    });

    let session = Session {
        id: session_id.clone(),
        connection_id: params.connection.id.clone(),
        name: params.connection.name.clone(),
        adapter: params.connection.adapter,
        client,
    };

    app.sessions.insert(session_id.clone(), session);

    Ok(json!({
        "session_id": session_id,
        "connection_id": params.connection.id,
        "name": params.connection.name,
        "adapter": "postgres",
        "server_version": null,
        "capabilities": {
            "querying": true,
            "catalog": true,
            "editable_grid": false
        }
    }))
}

fn disconnect(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: SessionRefParams = decode_params(request_id.clone(), params)?;
    let existed = app.sessions.remove(&params.session_id).is_some();
    app.queries.retain(|_, query| query.session_id != params.session_id);

    Ok(json!({
        "session_id": params.session_id,
        "disconnected": existed
    }))
}

fn ping_connection(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: SessionRefParams = decode_params(request_id.clone(), params)?;
    let session = session(app, request_id.clone(), &params.session_id)?;

    app.runtime.block_on(async {
        session
            .client
            .simple_query("select 1")
            .await
            .context("failed to ping PostgreSQL connection")
    }).map_err(|error| {
        request_error(
            request_id,
            "ping_failed",
            "connection",
            error.to_string(),
            Some("Reconnect the database session and try again.".to_string()),
        )
    })?;

    Ok(json!({
        "session_id": params.session_id,
        "ok": true
    }))
}

fn list_catalog(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: CatalogParams = decode_params(request_id.clone(), params)?;
    let session = session(app, request_id.clone(), &params.session_id)?;

    let nodes = match params.node_kind.as_str() {
        "root" => app.runtime.block_on(async {
            session.client.query(
                "select schema_name
                 from information_schema.schemata
                 where schema_name not in ('pg_catalog', 'information_schema', 'pg_toast')
                   and schema_name not like 'pg_temp_%'
                   and schema_name not like 'pg_toast_temp_%'
                 order by schema_name",
                &[],
            ).await.context("failed to load PostgreSQL schemas")
        }).map_err(|error| {
            request_error(
                request_id.clone(),
                "catalog_failed",
                "query",
                error.to_string(),
                Some("Refresh the explorer and confirm the connection is still valid.".to_string()),
            )
        })?.into_iter().map(|row| {
            let schema_name: String = row.get(0);
            json!({
                "kind": "schema",
                "name": schema_name,
                "path": [schema_name]
            })
        }).collect::<Vec<_>>(),
        "schema" => {
            let schema_name = params.node_path.first().cloned().ok_or_else(|| {
                request_error(
                    request_id.clone(),
                    "missing_schema",
                    "validation",
                    "schema node requests require node_path[1]".to_string(),
                    Some("Refresh the explorer and try again.".to_string()),
                )
            })?;

            app.runtime.block_on(async {
                session.client.query(
                    "select object_name, kind
                     from (
                       select c.relname as object_name,
                              case c.relkind
                                when 'v' then 'view'
                                when 'm' then 'materialized_view'
                                else 'table'
                              end as kind,
                              case c.relkind
                                when 'v' then 1
                                when 'm' then 2
                                else 3
                              end as sort_order
                       from pg_class c
                       join pg_namespace n on n.oid = c.relnamespace
                       where n.nspname = $1
                         and c.relkind in ('r', 'p', 'v', 'm')
                     ) objects
                     order by sort_order, object_name",
                    &[&schema_name],
                ).await.context("failed to load PostgreSQL schema objects")
            }).map_err(|error| {
                request_error(
                    request_id.clone(),
                    "catalog_failed",
                    "query",
                    error.to_string(),
                    Some("Refresh the explorer and confirm the connection is still valid.".to_string()),
                )
            })?.into_iter().map(|row| {
                let object_name: String = row.get(0);
                let kind: String = row.get(1);
                json!({
                    "kind": kind,
                    "name": object_name,
                    "path": [schema_name, object_name]
                })
            }).collect::<Vec<_>>()
        }
        other => {
            return Err(request_error(
                request_id,
                "unsupported_node_kind",
                "unsupported",
                format!("unsupported catalog node kind: {other}"),
                Some("Use `root` or `schema` for now.".to_string()),
            ));
        }
    };

    Ok(json!({
        "session_id": params.session_id,
        "node_kind": params.node_kind,
        "nodes": nodes
    }))
}

fn run_query(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: RunQueryParams = decode_params(request_id.clone(), params)?;
    let page_size = params.page_size.unwrap_or(100).max(1);
    let session = session(app, request_id.clone(), &params.session_id)?;
    let sql = params.sql.trim();

    if sql.is_empty() {
        return Err(request_error(
            request_id,
            "empty_query",
            "validation",
            "query text is empty".to_string(),
            Some("Write some SQL in the query buffer before running it.".to_string()),
        ));
    }

    let messages = app.runtime.block_on(async {
        session
            .client
            .simple_query(sql)
            .await
            .context("failed to execute PostgreSQL query")
    }).map_err(|error| {
        request_error(
            request_id.clone(),
            "query_failed",
            "query",
            error.to_string(),
            Some("Check the SQL text and try again.".to_string()),
        )
    })?;

    let mut columns = Vec::new();
    let mut rows = Vec::new();
    let mut command_tag = None;

    for message in messages {
        match message {
            SimpleQueryMessage::Row(row) => {
                if columns.is_empty() {
                    columns = row.columns().iter().map(|column| column.name().to_string()).collect();
                }

                let values = (0..row.len())
                    .map(|index| match row.get(index) {
                        Some(value) => Value::String(value.to_string()),
                        None => Value::Null,
                    })
                    .collect::<Vec<_>>();

                rows.push(values);
            }
            SimpleQueryMessage::CommandComplete(tag) => {
                command_tag = Some(tag.to_string());
            }
            _ => {}
        }
    }

    let query_id = app.next_query_id();
    let cached_query = CachedQuery {
        id: query_id.clone(),
        session_id: params.session_id.clone(),
        columns,
        rows,
        command_tag,
        page_size,
    };

    let first_page = page_payload(&cached_query, 0);
    let columns = cached_query.columns.clone();
    let command_tag = cached_query.command_tag.clone();
    let row_count = cached_query.rows.len();

    app.queries.insert(query_id.clone(), cached_query);

    Ok(json!({
        "query_id": query_id,
        "session_id": params.session_id,
        "columns": columns,
        "row_count": row_count,
        "command_tag": command_tag,
        "page": first_page
    }))
}

fn fetch_page(
    app: &mut AppState,
    request_id: Value,
    params: Value,
) -> std::result::Result<Value, ErrorResponse> {
    let params: FetchPageParams = decode_params(request_id.clone(), params)?;
    let page_index = params.page_index.unwrap_or(0);

    let query = app.queries.get(&params.query_id).ok_or_else(|| {
        request_error(
            request_id,
            "unknown_query",
            "validation",
            format!("unknown query id: {}", params.query_id),
            Some("Run the query again before fetching more pages.".to_string()),
        )
    })?;

    Ok(page_payload(query, page_index))
}

fn page_payload(query: &CachedQuery, page_index: usize) -> Value {
    let start = page_index.saturating_mul(query.page_size);
    let end = (start + query.page_size).min(query.rows.len());
    let rows = if start < query.rows.len() {
        query.rows[start..end].to_vec()
    } else {
        Vec::new()
    };

    json!({
        "query_id": query.id,
        "page_index": page_index,
        "page_size": query.page_size,
        "total_rows": query.rows.len(),
        "has_more": end < query.rows.len(),
        "columns": query.columns,
        "rows": rows
    })
}

fn session<'a>(
    app: &'a AppState,
    request_id: Value,
    session_id: &str,
) -> std::result::Result<&'a Session, ErrorResponse> {
    app.sessions.get(session_id).ok_or_else(|| {
        request_error(
            request_id,
            "unknown_session",
            "validation",
            format!("unknown session id: {session_id}"),
            Some("Reconnect the database connection and try again.".to_string()),
        )
    })
}

fn decode_params<T: for<'de> Deserialize<'de>>(
    request_id: Value,
    params: Value,
) -> std::result::Result<T, ErrorResponse> {
    serde_json::from_value(params).map_err(|error| {
        request_error(
            request_id,
            "invalid_params",
            "validation",
            format!("invalid params: {error}"),
            Some("Check the plugin request payload.".to_string()),
        )
    })
}

fn request_error(
    id: Value,
    code: &'static str,
    category: &'static str,
    message: String,
    user_action: Option<String>,
) -> ErrorResponse {
    ErrorResponse {
        id,
        error: ErrorPayload {
            code,
            category,
            message,
            details: None,
            retryable: false,
            user_action,
        },
    }
}

fn protocol_error(
    id: Value,
    code: &'static str,
    message: String,
    user_action: Option<String>,
) -> ErrorResponse {
    ErrorResponse {
        id,
        error: ErrorPayload {
            code,
            category: "protocol",
            message,
            details: None,
            retryable: false,
            user_action,
        },
    }
}

fn write_json_line<T: Serialize>(stdout: &mut impl Write, payload: &T) -> Result<()> {
    serde_json::to_writer(&mut *stdout, payload).context("failed to serialize response")?;
    stdout.write_all(b"\n").context("failed to write newline")?;
    stdout.flush().context("failed to flush stdout")?;
    Ok(())
}
