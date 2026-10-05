# Etapa 1: Compilación
FROM ubuntu:22.04 AS build-env
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git wget unzip libgconf-2-4 gdb libstdc++6 libglu1-mesa \
    fonts-droid-fallback python3 sed ca-certificates \
    cmake ninja-build pkg-config libgtk-3-dev \
    build-essential clang chromium-browser \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN git config --global --add safe.directory /usr/local/flutter
RUN flutter config --enable-web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .

RUN flutter clean
# Opcional (Railway): en el servicio de la web, define variable de entorno en tiempo de build
# API_BASE_URL=https://TU-SERVICIO-API.up.railway.app/api para que el login apunte al backend.
ARG API_BASE_URL=""
RUN if [ -n "$API_BASE_URL" ]; then \
      flutter build web --release --no-web-resources-cdn --pwa-strategy=none \
        --dart-define=API_BASE_URL="$API_BASE_URL"; \
    else \
      flutter build web --release --no-web-resources-cdn --pwa-strategy=none; \
    fi

# Etapa 2: Nginx para servir la web
FROM nginx:alpine
COPY --from=build-env /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
