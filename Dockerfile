# syntax=docker/dockerfile:1.7
FROM node:24-bookworm-slim AS assets

WORKDIR /app
COPY frontend/package.json frontend/package-lock.json ./frontend/
RUN npm --prefix frontend ci --no-audit --no-fund
COPY frontend ./frontend
COPY replica/design/tokens.css ./replica/design/tokens.css
RUN npm --prefix frontend run build && test -f public/app/index.html

FROM ruby:3.3-slim AS gems

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test \
    BUNDLE_JOBS=4
COPY Gemfile Gemfile.lock ./
RUN bundle config set without test \
    && bundle install \
    && rm -rf /usr/local/bundle/cache

FROM ruby:3.3-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 ots \
    && useradd --uid 10001 --gid ots --no-create-home --shell /usr/sbin/nologin ots

WORKDIR /app
ENV RACK_ENV=production \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=test \
    PORT=3000

COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock ./
COPY config.ru ./
COPY config ./config
COPY lib ./lib
COPY --from=assets /app/public/app ./public/app
RUN mkdir -p tmp && chown -R ots:ots /app

USER ots
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null || exit 1

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
