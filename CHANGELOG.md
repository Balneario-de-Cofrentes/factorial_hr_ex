# Changelog

## 0.2.1 - 2026-06-19

- Rejects selectorless `bulk_delete_shifts/2` requests before calling
  Factorial's destructive bulk-delete endpoint.
- Validates required shift fields locally and parses numeric shift IDs provided
  as strings.
- Returns `:unexpected_response` for unknown successful bulk-create payloads.
- Preserves SDK authentication and JSON headers when callers add custom
  `req_options[:headers]`.
- Returns structured `:invalid_config` errors for invalid URL/version options.
- Avoids repeated list appends while collecting paginated results.

## 0.2.0 - 2026-06-18

- Renames the package from `factorial_hr_ex` to `factorial_hr` before the first
  Hex.pm publication.
- Renames the public module from `FactorialHREx` to `FactorialHR`.
- Refines public README, scope, security and contribution documentation.
- Aligns generated documentation source links with the release tag.

## 0.1.0 - 2026-06-18

- Initial generic Factorial HR client.
- Supports API key and bearer auth, date-based API versions, cursor pagination,
  employee/location/work-area/team catalogs, attendance shifts,
  shift-management CRUD helpers, contract versions and compensations.
- Adds structured errors and optional telemetry events.
