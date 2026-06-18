# Contributing

Thanks for improving `FactorialHR`.

This package is intentionally small and framework-agnostic. Keep Phoenix, Ecto,
tenant mappings, staffing rules, customer payloads and real credentials in host
applications.

## Development

```bash
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
```

Tests use `Req.Test` and must not call the live Factorial API.

## Pull Requests

- Keep changes focused.
- Add or update tests for behavior changes.
- Preserve the public API unless the version bump makes a breaking change
  explicit.
- Link to Factorial's public API documentation instead of copying proprietary
  docs or generated schemas into this repository.

## Release Checklist

```bash
mix hex.audit
mix hex.build --unpack
mix hex.publish --dry-run
```

After publishing, verify the package can be fetched and compiled from a clean
Mix project.
