---
name: testing-oficina-production
description: Run sanitized end-to-end validation of the deployed Oficina production environment across Backend, API Gateway, EKS, notifications, DLQ, and logs.
---

# Oficina production E2E testing

## Devin Secrets Needed

- `AWS_ACADEMY_CREDENTIALS`: temporary AWS Academy `[default]` credential block.

Application secrets must be read at runtime from Kubernetes Secret `oficina-secrets`; never copy
values into a plan, script, screenshot, recording, or report.

## Safe setup

1. Normalize the AWS credential block into `~/.aws/credentials` with mode `0600`. Secure-channel
   multiline values may arrive flattened into one line. Locate the three literal key names
   (`aws_access_key_id`, `aws_secret_access_key`, `aws_session_token`) and rebuild the INI without
   printing values; validate only key names and value lengths.
2. Verify only account/ARN using `aws sts get-caller-identity`.
3. Run `aws eks update-kubeconfig --name oficina-production --region us-west-2`.
4. Older AWS CLI releases may emit `client.authentication.k8s.io/v1alpha1`, rejected by modern
   kubectl. Prefer upgrading to AWS CLI v2. A temporary fallback wrapper can pass all kubeconfig
   arguments to `aws "$@"` and replace only the ExecCredential apiVersion with `v1beta1`.
5. Confirm namespace `oficina-production`, pods, and Secret key names before reading any values.

## Synthetic-data discipline

- Normalize and search the requested CPF before creating a client. Reuse an active matching client
  without editing it; create only when absent.
- Search plate `TST3A32` under that client and reuse it without edits; create only when absent.
- Create new OS, technician, second client, and catalog items with a run-specific marker.
- Drive state transitions only on the OS created during the current run.

## Runtime flow

- Public: health, Swagger UI, OpenAPI, administrative login, `POST /auth/cpf`.
- Role checks: technician must receive 403 on an administrative endpoint; technician can add an OS
  item; employee role inherits technician access; employee token cannot use client-only routes.
- JWT: validate three segments, RS256, issuer, audience, `CLIENTE`, `sub == client_id`, 900-second
  TTL, CPF absence, and verify the signature with `SERVERLESS_JWT_PUBLIC_KEY`.
- Isolation: a second synthetic client must receive non-enumerating 404 on the owner's OS. Inspect
  structured fields for ownership leakage; do not search for short numeric IDs as substrings.
- OS states: `RECEBIDA`, `EM_DIAGNOSTICO`, `AGUARDANDO_APROVACAO`, `EM_EXECUCAO`,
  `AGUARDANDO_PAGAMENTO`, `PAGA`, `ENTREGUE`.

## Notifications and logs

- Production notification JSON uses `destinatario`, `assunto`, and `corpo` (not `mensagem`).
- Validate 401 without `X-Notification-Key`, then 202 with the key and a synthetic request ID.
- Correlate `ACCEPTED` in notification-ingress and `PROCESSED` in notification-delivery. Production
  normally uses delivery mode `log`; query the deployed Lambda configuration rather than assuming.
- Require the notification DLQ to be empty before and after the test.
- Audit Backend pod logs, the four functional Lambda log groups, and API Gateway access logs using
  exact in-memory values. Print only counts/booleans. Also detect JWT-shaped strings and populated
  Authorization Bearer headers.
- API Gateway access-log objects should contain only the Terraform allowlisted technical fields.

## Evidence

Record only browser-visible public behavior and a sanitized runtime-results view. Never type or show
JWTs, passwords, keys, CPF values, request payloads, or raw logs. Mask CPF and use only synthetic OS
identifiers in visual evidence.
