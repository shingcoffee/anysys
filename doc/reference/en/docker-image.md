---
title: "Docker image"
summary: "Build the production Alpine image and run it with RAILS_MASTER_KEY, APP_HOST, and a volume on /rails/storage."
---

## Summary

The production container is a multi-stage build from `ruby:3.2.8-alpine` in the repository-root `Dockerfile`. That official Alpine tag is the smallest Ruby base this app can run: Thruster is a static binary, and `nokogiri`, `sqlite3`, `ffi`, and `tailwindcss-ruby` publish musl builds in `Gemfile.lock`. The final image does not include compilers, development/test gems, the Tailwind CLI, specs, or `config/master.key`.

The process listens on port 80 through Thruster, with Puma behind it. A single container runs Solid Queue inside Puma when `SOLID_QUEUE_IN_PUMA` is set. SQLite files, Solid Cache/Queue/Cable databases, and Active Storage uploads live under `/rails/storage` and must be a persistent volume. See [Background jobs](background-jobs) for the four production SQLite databases.

Measured on the build host after a full `docker build`: `ruby:3.2.8-alpine` is 66.3MB, `ruby:3.2.8-slim` is 147MB, `ruby:3.2.8` is 992MB, and the shipped `anysys` image is about 402MB. Those numbers move with gem and Alpine package versions.

## Flow

```text
docker build -t anysys .
        |
        v
ruby:3.2.8-alpine
        |
        +-- base: ffmpeg, vips, ImageMagick, jemalloc, sqlite, bash
        |
        +-- build: bundle (BUNDLE_WITHOUT=development:test)
        |          SECRET_KEY_BASE_DUMMY=1 assets:precompile
        |          drop Tailwind CLI, strip .so / Thruster
        |
        v
final image  uid 1000 (rails)  EXPOSE 80
CMD ./bin/thrust ./bin/rails server

docker run -e RAILS_MASTER_KEY -e APP_HOST \
           -e SOLID_QUEUE_IN_PUMA=true \
           -v anysys_storage:/rails/storage -p 80:80
        |
        v
bin/docker-entrypoint
        |
        last args ./bin/rails server -> bin/rails db:prepare
        |
        v
Thruster :80  ->  Puma :3000  ->  GET /up (SSL redirect excluded)
```

## Implementation

Build from the repository root. The daemon must be running, and the invoking user must be allowed to talk to it.

```bash
docker build -t anysys .
```

`.dockerignore` keeps secrets and non-runtime trees out of the build context: `config/master.key`, `config/credentials/*.key`, `.env*`, `.git`, `spec`, `docs`, `doc/plans`, `node_modules`, coverage, and local `storage/` / `tmp/` / `log/` contents. `doc/reference` and `doc/customer` stay in the image because this reference and the customer Help guides are served from those trees.

The build stage precompiles assets with `SECRET_KEY_BASE_DUMMY=1`. `CanonicalUrlOptions.assets_only_build?` treats that as an assets-only boot, so `APP_HOST` is not required during `assets:precompile`. A server boot still requires the real host.

Run the image with the production secret and a public hostname. Do not bake `config/master.key` into the image; pass it at runtime. `config/credentials.yml.enc` is in the image and is decrypted with that key.

```bash
docker run --rm -p 80:80 \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e APP_HOST=your.domain.example \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v anysys_storage:/rails/storage \
  anysys
```

Required environment:

| Variable | Purpose |
| --- | --- |
| `RAILS_MASTER_KEY` | Decrypts `config/credentials.yml.enc` |
| `APP_HOST` | Canonical hostname for mail and out-of-request URLs. Hostname or IP only, no scheme, port, path, or userinfo. Production rejects loopback and wildcard hosts. |
| `SOLID_QUEUE_IN_PUMA` | Set to `true` so the web process runs the Solid Queue supervisor. Omit only when a separate `bin/jobs` container exists. |

Optional environment:

| Variable | Default | Purpose |
| --- | --- | --- |
| `APP_PROTOCOL` | `https` | Canonical URL scheme. Production requires `https`. |
| `APP_PORT` | unset | Optional canonical port, 1–65535. |
| `RAILS_LOG_LEVEL` | `info` | Rails log level (stdout). |
| `RAILS_MAX_THREADS` | `3` | Puma threads and SQLite pool. |
| `WEB_CONCURRENCY` | unset (one worker) | Puma workers. |
| `JOB_CONCURRENCY` | `1` | Solid Queue worker processes. |

`compose.yaml` is the same mapping when Compose is installed: port 80, the two required variables, `SOLID_QUEUE_IN_PUMA=true`, `APP_PROTOCOL` defaulting to `https`, named volume `anysys_storage`, and `init: true`.

```bash
RAILS_MASTER_KEY="$(cat config/master.key)" APP_HOST=your.domain.example docker compose up --build
```

Kamal (`config/deploy.yml`) builds this same `Dockerfile`, injects `RAILS_MASTER_KEY`, sets `SOLID_QUEUE_IN_PUMA`, and mounts `anysys_storage` on `/rails/storage`.

The entrypoint creates `tmp/pids`, `storage`, and `log`, then runs `bin/rails db:prepare` when the last two arguments are `./bin/rails` and `server` (Thruster's default CMD). After that it `exec`s the given command. The process user is `1000:1000` (`rails`). The image `HEALTHCHECK` GETs `http://127.0.0.1/up` with Ruby's `Net::HTTP`. Production `force_ssl` skips the redirect for `/up`.

Runtime packages that must stay in the image: `ffmpeg` (speech-to-text transcode), `vips` (Active Storage variants), ImageMagick (`mini_magick` barcodes), `jemalloc` (`LD_PRELOAD`), and `sqlite`. See [Speech to text](speech-to-text) and [Background jobs](background-jobs).

## Where to pay attention

:::attention
Production boot calls `ENV.fetch("APP_HOST")`. `localhost`, `*.localhost`, loopback addresses, and a wildcard IP fail `CanonicalUrlOptions.validate`. `APP_PROTOCOL` must be `https` in production. Missing or invalid values raise at boot instead of publishing a fabricated origin.
:::

:::attention
`.dockerignore` excludes `config/master.key`. Passing the key as a build `ARG` or `COPY` would bake the secret into a layer. Keep it in the `docker run` `-e` (or Compose/Kamal secrets).
:::

:::attention
Without `-v …:/rails/storage`, SQLite and uploads live in the container writable layer and disappear when the container is removed. A first use of a Docker named volume copies the image's `storage/` (uid 1000) into the volume. A bind mount of a host directory that is owned by root will fail `db:prepare` as user 1000.
:::

:::attention
`config.assume_ssl` and `config.force_ssl` are on in production. Terminate TLS at the reverse proxy or load balancer in front of port 80. `GET /up` is the health endpoint and is excluded from the HTTP-to-HTTPS redirect.
:::

:::note
Image size is dominated by Alpine ffmpeg/vips/ImageMagick (~167MB) and the production gem bundle (~176MB, Stripe and Twilio clients are the largest). The Tailwind standalone CLI is deleted after `assets:precompile`. Test gems are excluded with `BUNDLE_WITHOUT=development:test`.
:::

## Key code

```bash
docker build -t anysys .
```

```bash
docker run --rm -p 80:80 \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e APP_HOST=your.domain.example \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v anysys_storage:/rails/storage \
  anysys
```

```bash
# Confirm the process is up (maps host 80 to container 80).
curl -sS -D - -o /dev/null http://127.0.0.1/up
```

```dockerfile
# Dockerfile
FROM docker.io/library/ruby:${RUBY_VERSION}-alpine AS base
# …

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
```

```bash
# bin/docker-entrypoint
if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi
exec "${@}"
```
