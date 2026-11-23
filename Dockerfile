# syntax=docker/dockerfile:1
# check=error=true
#
# Production image. Alpine is the smallest official Ruby base that still
# runs this app: Thruster is a static binary, and native gems (nokogiri,
# sqlite3, ffi, tailwindcss-ruby) publish musl builds in Gemfile.lock.
#
#   sudo docker build -t anysys .
#   sudo docker run --rm -p 80:80 \
#     -e RAILS_MASTER_KEY=<config/master.key> \
#     -e APP_HOST=example.com \
#     -e SOLID_QUEUE_IN_PUMA=true \
#     -v anysys_storage:/rails/storage \
#     anysys

ARG RUBY_VERSION=3.2.8
FROM docker.io/library/ruby:${RUBY_VERSION}-alpine AS base

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/lib/libjemalloc.so.2"

# ffmpeg (STT), vips (Active Storage), ImageMagick (barcode JPG).
RUN apk add --no-cache \
      bash \
      ca-certificates \
      ffmpeg \
      imagemagick \
      jemalloc \
      libffi \
      sqlite \
      tzdata \
      vips \
      yaml

FROM base AS build

RUN apk add --no-cache \
      build-base \
      linux-headers \
      pkgconf \
      sqlite-dev \
      yaml-dev

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git

COPY . .

# SECRET_KEY_BASE_DUMMY is an assets-only boot; APP_HOST is not required.
# Drop the Tailwind CLI after precompile (~40MB) and strip native extensions.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf tmp/cache "${BUNDLE_PATH}"/ruby/*/gems/tailwindcss-ruby-*/exe && \
    find "${BUNDLE_PATH}" -name "*.so" -exec strip --strip-unneeded {} +

FROM base

RUN addgroup -g 1000 -S rails && \
    adduser -u 1000 -S -D -G rails -h /home/rails -s /bin/bash rails && \
    mkdir -p db log tmp/pids storage && \
    chown -R rails:rails db log tmp storage /home/rails

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD ruby -e 'require "net/http"; res = Net::HTTP.get_response(URI("http://127.0.0.1/up")); exit(res.is_a?(Net::HTTPSuccess) ? 0 : 1)'

CMD ["./bin/thrust", "./bin/rails", "server"]
