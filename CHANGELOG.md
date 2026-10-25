# Changelog

## 0.2.1 - 2026-10-25

### Fixed

- `Letterapp::Client` no longer breaks Active Support's `present?`, `blank?`
  and `presence`. 0.2.0 had a private `blank?(value)` helper that shadowed
  `Object#blank?`, so in a Rails app `client.present?` and `client.presence`
  raised `ArgumentError: wrong number of arguments (given 0, expected 1)`, and
  `client.blank?` raised `NoMethodError`. The helper is now named `missing?`.

## 0.2.0 - 2026-08-20

### Added

- `send_email` for transactional email (`POST /v1/send`), with
  `idempotency_key:` for replay-safe retries.
- `Letterapp::DeliveryMethod`, registered as `:letter` with ActionMailer in a
  Rails app.
- `Letterapp::Error#code` and `#reason`, from the API's error body.

## 0.1.0 - 2026-05-29

- First release: `identify`, `group` and `track`, auto-batched in the
  background, with retries and idempotent message IDs.
