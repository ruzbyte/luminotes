# Build context is the repo root (see docker-compose.yml) so the shared
# luminotes_sync_core package is available alongside the server.
FROM dart:stable AS build
WORKDIR /app
COPY packages/ packages/
COPY server/ server/
WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o /app/luminotes-server

FROM debian:stable-slim AS runtime
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/luminotes-server /usr/local/bin/luminotes-server
ENV DATA_DIR=/data
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["luminotes-server"]
CMD ["serve"]
