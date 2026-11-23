---
title: "Docker 镜像"
summary: "构建基于 Alpine 的生产镜像，并以 RAILS_MASTER_KEY、APP_HOST 以及挂载到 /rails/storage 的数据卷运行。"
---

## 概要

生产容器由仓库根目录 `Dockerfile` 多阶段构建，基础镜像为 `ruby:3.2.8-alpine`。这是本应用能跑起来的最小官方 Ruby 基础镜像：Thruster 是静态二进制，`nokogiri`、`sqlite3`、`ffi`、`tailwindcss-ruby` 均在 `Gemfile.lock` 中提供 musl 构建。最终镜像不含编译器、development/test 组的 gem、Tailwind CLI、测试代码或 `config/master.key`。

进程经 Thruster 监听 80 端口，Puma 在其后。设置 `SOLID_QUEUE_IN_PUMA` 时，单个容器在 Puma 内运行 Solid Queue。SQLite 文件、Solid Cache／Queue／Cable 数据库以及 Active Storage 上传均位于 `/rails/storage`，必须使用持久卷。四个生产 SQLite 库见[后台任务](background-jobs)。

在构建主机上完整执行 `docker build` 后测得：`ruby:3.2.8-alpine` 为 66.3MB，`ruby:3.2.8-slim` 为 147MB，`ruby:3.2.8` 为 992MB，打好的 `anysys` 镜像约 402MB。具体数字会随 gem 与 Alpine 软件包版本变化。

## 流程

```text
docker build -t anysys .
        |
        v
ruby:3.2.8-alpine
        |
        +-- base：ffmpeg、vips、ImageMagick、jemalloc、sqlite、bash
        |
        +-- build：bundle（BUNDLE_WITHOUT=development:test）
        |          SECRET_KEY_BASE_DUMMY=1 assets:precompile
        |          删除 Tailwind CLI，strip .so／Thruster
        |
        v
最终镜像  uid 1000（rails）  EXPOSE 80
CMD ./bin/thrust ./bin/rails server

docker run -e RAILS_MASTER_KEY -e APP_HOST \
           -e SOLID_QUEUE_IN_PUMA=true \
           -v anysys_storage:/rails/storage -p 80:80
        |
        v
bin/docker-entrypoint
        |
        末两参数为 ./bin/rails server → bin/rails db:prepare
        |
        v
Thruster :80  →  Puma :3000  →  GET /up（排除 SSL 重定向）
```

## 实现

在仓库根目录构建。本机须已启动 Docker 守护进程，且当前用户有权访问该守护进程。

```bash
docker build -t anysys .
```

`.dockerignore` 把密钥与非运行时目录挡在构建上下文之外：`config/master.key`、`config/credentials/*.key`、`.env*`、`.git`、`spec`、`docs`、`doc/plans`、`node_modules`、覆盖率报告，以及本地 `storage/`、`tmp/`、`log/` 内容。`doc/reference` 与 `doc/customer` 仍打进镜像，因为本参考与客户帮助文档从这两棵树提供。

构建阶段用 `SECRET_KEY_BASE_DUMMY=1` 预编译资源。`CanonicalUrlOptions.assets_only_build?` 将其视为仅资源构建，因此 `assets:precompile` 不需要 `APP_HOST`。真正启动服务器时仍必须提供真实主机名。

运行镜像时传入生产密钥与对外主机名。不要把 `config/master.key` 打进镜像，只在运行时传入。`config/credentials.yml.enc` 已在镜像内，用该密钥解密。

```bash
docker run --rm -p 80:80 \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  -e APP_HOST=your.domain.example \
  -e SOLID_QUEUE_IN_PUMA=true \
  -v anysys_storage:/rails/storage \
  anysys
```

必填环境变量：

| 变量 | 用途 |
| --- | --- |
| `RAILS_MASTER_KEY` | 解密 `config/credentials.yml.enc` |
| `APP_HOST` | 邮件及请求外 URL 的规范主机名。只能是主机名或 IP，不含协议、端口、路径或用户信息。生产环境拒绝回环与通配地址。 |
| `SOLID_QUEUE_IN_PUMA` | 设为 `true`，由 Web 进程运行 Solid Queue 监管器。仅在另有 `bin/jobs` 容器时才可省略。 |

可选环境变量：

| 变量 | 默认 | 用途 |
| --- | --- | --- |
| `APP_PROTOCOL` | `https` | 规范 URL 协议。生产环境必须为 `https`。 |
| `APP_PORT` | 未设置 | 可选规范端口，范围 1–65535。 |
| `RAILS_LOG_LEVEL` | `info` | Rails 日志级别（标准输出）。 |
| `RAILS_MAX_THREADS` | `3` | Puma 线程数与 SQLite 连接池。 |
| `WEB_CONCURRENCY` | 未设置（一个 worker） | Puma worker 数。 |
| `JOB_CONCURRENCY` | `1` | Solid Queue worker 进程数。 |

若已安装 Compose，`compose.yaml` 是同一套映射：80 端口、两个必填变量、`SOLID_QUEUE_IN_PUMA=true`、`APP_PROTOCOL` 默认为 `https`、命名卷 `anysys_storage`，以及 `init: true`。

```bash
RAILS_MASTER_KEY="$(cat config/master.key)" APP_HOST=your.domain.example docker compose up --build
```

Kamal（`config/deploy.yml`）使用同一份 `Dockerfile`，注入 `RAILS_MASTER_KEY`，设置 `SOLID_QUEUE_IN_PUMA`，并把 `anysys_storage` 挂到 `/rails/storage`。

入口脚本创建 `tmp/pids`、`storage`、`log`；当末两参数为 `./bin/rails` 与 `server` 时（Thruster 的默认 CMD）执行 `bin/rails db:prepare`，然后 `exec` 给定命令。进程用户为 `1000:1000`（`rails`）。镜像 `HEALTHCHECK` 用 Ruby `Net::HTTP` 请求 `http://127.0.0.1/up`。生产环境的 `force_ssl` 对 `/up` 不做跳转。

运行时必须保留的软件包：`ffmpeg`（语音转写转码）、`vips`（Active Storage 变体）、ImageMagick（`mini_magick` 条码）、`jemalloc`（`LD_PRELOAD`）、`sqlite`。见[语音转文字](speech-to-text)与[后台任务](background-jobs)。

## 需要特别注意

:::attention
生产启动会调用 `ENV.fetch("APP_HOST")`。`localhost`、`*.localhost`、回环地址和通配 IP 无法通过 `CanonicalUrlOptions.validate`。生产环境的 `APP_PROTOCOL` 必须为 `https`。缺失或非法的值会在启动时抛错，而不会发布伪造的站点来源。
:::

:::attention
`.dockerignore` 排除 `config/master.key`。用构建 `ARG` 或 `COPY` 传入密钥会把秘密写进镜像层。只通过 `docker run` 的 `-e`（或 Compose／Kamal 密钥）传递。
:::

:::attention
若不使用 `-v …:/rails/storage`，SQLite 与上传文件会落在容器可写层，容器删除后即消失。首次使用 Docker 命名卷时，镜像内 `storage/`（uid 1000）会复制进卷。若把主机上 root 拥有的目录绑定挂载进去，uid 1000 执行 `db:prepare` 会失败。
:::

:::attention
生产环境开启 `config.assume_ssl` 与 `config.force_ssl`。在 80 端口前的反向代理或负载均衡上终止 TLS。`GET /up` 是健康检查，且排除在 HTTP 到 HTTPS 的重定向之外。
:::

:::note
镜像体积主要来自 Alpine 的 ffmpeg／vips／ImageMagick（约 167MB）和生产 gem（约 176MB，Stripe 与 Twilio 客户端最大）。`assets:precompile` 之后会删除 Tailwind 独立 CLI。测试用 gem 由 `BUNDLE_WITHOUT=development:test` 排除。
:::

## 关键代码

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
# 确认进程已起来（将主机 80 映射到容器 80）。
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
