# Security Policy

## Supported Versions

Security fixes are released for the latest published minor version.

## Reporting a Vulnerability

Please do not open public issues for security reports.

Use GitHub private vulnerability reporting when available, or contact the
maintainers through the repository owner organization. Include:

- affected version
- impact
- reproduction steps
- any relevant request/response shape with credentials and personal data
  removed

We will acknowledge valid reports, coordinate a fix privately and publish a
patched release when needed.

## Credential Handling

`FactorialHR` accepts API keys and bearer access tokens at runtime. The
library does not store credentials, refresh tokens or tenant data.

Never include real Factorial credentials, employee data or customer payloads in
issues, pull requests, tests or documentation.
