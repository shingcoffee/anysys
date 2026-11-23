# Anysys

A multi-tenant Rails 8.1 application built with Ruby 3.2.8, ViewComponent, Stimulus, TailwindCSS, and the Trailblazer/dry-rb families.

## Documentation

- [`docs/README.md`](docs/README.md) — overview of the documentation layout.
- [`docs/architecture/`](docs/architecture/) — architecture and design patterns.
- [`docs/features/`](docs/features/) — feature-specific documentation.
- [`docs/guides/`](docs/guides/) — step-by-step guides.
- [`AGENTS.md`](AGENTS.md) — conventions for Cursor / AI-assisted development.
- [`.cursor/`](.cursor/) — project rules, skills, subagents, and hooks.

## Development Quick Reference

* **Ruby version:** 3.2.8
* **Rails version:** 8.1.2
* **Setup:** `bin/setup`
* **Run server:** `rm -f public/assets/.manifest.json && SKIP_AUTH=1 bin/rails server -b 0.0.0.0 -p 3000`
* **Run tests:**
  * Targeted: `bundle exec rspec spec/path/to/affected_spec.rb`
  * Full suite (parallel): `bin/rails parallel:prepare && bin/rails parallel:spec`
  * Full suite (serial): `bundle exec rspec`
  * JavaScript: `npm test`
* **Lint:** `bin/rubocop`
* **Security scans:** `bin/brakeman --no-pager`, `bin/bundler-audit`, `bin/importmap audit`
