# FactorialHR

[![CI](https://github.com/Balneario-de-Cofrentes/factorial_hr/actions/workflows/ci.yml/badge.svg)](https://github.com/Balneario-de-Cofrentes/factorial_hr/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/factorial_hr.svg)](https://hex.pm/packages/factorial_hr)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/factorial_hr)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Framework-agnostic Elixir client for the public Factorial HR REST API.

This library is intentionally generic: it handles authentication, versioned API
URLs, cursor pagination, common HR resources, shift management, attendance
shifts and contract resources. It does not contain Phoenix, Ecto, tenant
mappings, staffing rules, private fixtures or customer-specific data.

## Installation

```elixir
def deps do
  [
    {:factorial_hr, "~> 0.2.0"}
  ]
end
```

## Usage

```elixir
opts = [
  api_key: System.fetch_env!("FACTORIAL_API_KEY"),
  api_version: "2026-04-01"
]

{:ok, employees} = FactorialHR.list_employees([only_active: true], opts)

{:ok, shifts} =
  FactorialHR.list_shifts(
    [
      employee_ids: [123, 456],
      start_at: "2026-06-01",
      end_at: "2026-06-30",
      only_states: ["published"]
    ],
    opts
  )
```

Bearer access-token usage:

```elixir
opts = [
  auth_mode: :bearer,
  access_token: token,
  api_version: "2026-04-01"
]

FactorialHR.list_locations([], opts)
```

This package does not implement the OAuth authorization-code, refresh-token or
revocation flows. Applications that need OAuth should obtain and refresh tokens
in their own auth layer, then pass the access token to `FactorialHR`.

## Configuration

Prefer explicit options from your host application configuration:

```elixir
[
  api_key: "...",
  auth_mode: :api_key,
  base_url: "https://api.factorialhr.com",
  api_version: "2026-04-01",
  company_id: 123,
  author_id: 456,
  req_options: [retry: :transient]
]
```

Retries are disabled by default. Configure them through `req_options` when the
calling application wants retry behavior.

For scripts, the client can fall back to:

- `FACTORIAL_API_KEY`
- `FACTORIAL_ACCESS_TOKEN`
- `FACTORIAL_API_TOKEN`
- `FACTORIAL_API_URL`
- `FACTORIAL_API_VERSION`

## Supported Resources

- `list_employees/2`
- `list_locations/2`
- `list_work_areas/2`
- `list_teams/2`
- `list_team_employee_ids/1`
- `list_attendance_shifts/4`
- `list_shifts/2`
- `create_shift/2`
- `bulk_create_shifts/2`
- `delete_shift/2`
- `bulk_delete_shifts/2`
- `list_contract_versions/2`
- `list_compensations/2`
- Low-level `get/3`, `post/3`, `delete/2` and `all/4`

## Error Handling

Operations return `{:ok, value}` or `{:error, %FactorialHR.Error{}}`.
Low-level `get/3`, `post/3` and `delete/2` return `{:ok, %Req.Response{}}`
for 2xx responses and structured errors for non-2xx responses.

```elixir
case FactorialHR.list_employees([], opts) do
  {:ok, employees} ->
    employees

  {:error, %FactorialHR.Error{type: :http_error, status: 401}} ->
    {:error, :factorial_auth_failed}
end
```

`bulk_delete_shifts/2` accepts either a non-empty list of integer shift IDs or
a map/keyword list of Factorial bulk-delete filters. Empty ID lists and mixed
ID types are rejected locally before any API request is sent.

## API Versioning

Factorial uses date-based API versions. The default version is `2026-04-01`,
and callers can override it with `api_version: "YYYY-MM-DD"` or by passing a
full Factorial API URL in `api_url`.

```elixir
FactorialHR.list_employees([], api_key: api_key, api_version: "2026-07-01")
```

## Telemetry

The client emits optional telemetry events when `:telemetry` is available:

- `[:factorial_hr, :request, :start]`
- `[:factorial_hr, :request, :stop]`
- `[:factorial_hr, :request, :exception]`

Request metadata includes `:method`, `:path` and `:url`. Successful stop events
also include `:status`; exception events include `:kind` and `:reason`.

## Development

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

Tests use `Req.Test` and do not call the live Factorial API.

## Factorial API References

- API keys use the `x-api-key` header:
  https://apidoc.factorialhr.com/docs/api-keys
- Factorial states that API keys are for internal company integrations and
  marketplace integrations must use OAuth:
  https://apidoc.factorialhr.com/docs/authentication
- Public API versions are date-based and supported for one year:
  https://apidoc.factorialhr.com/docs/api-versioning
- Cursor pagination uses `after_id` / `before_id` and `meta.end_cursor`:
  https://apidoc.factorialhr.com/docs/pagination

## Scope and Security

`FactorialHR` is a generic API client. Application-specific mappings,
production credentials, tenant payloads and employee data belong in the host
application, not in this library.

Endpoint behavior should be documented by linking to Factorial's public API
reference instead of vendoring copied docs or generated schemas.

Security reports are handled privately; see [SECURITY.md](SECURITY.md).

## Contributing

Issues and pull requests are welcome. Please keep this package generic and
framework-independent; tenant-specific behavior belongs in host applications.
See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.
