# syntax=docker/dockerfile:1

# ---------- Frontend Builder ----------
FROM node:20-alpine AS frontend-builder

WORKDIR /app/client

COPY client/package*.json ./
RUN npm install --legacy-peer-deps

COPY client/ ./
RUN npm run build

# ---------- Backend Builder ----------
FROM node:20-alpine AS backend-builder

WORKDIR /app/server

COPY server/package*.json ./
RUN npm install --legacy-peer-deps

COPY server/ ./

# ---------- Unified Runtime ----------
FROM nginx:alpine AS runtime

RUN apk add --no-cache nodejs npm

# Nginx runtime dirs
RUN mkdir -p /run/nginx /etc/nginx/http.d /etc/nginx/conf.d

# Nginx config: serve SPA on 80, proxy /api to backend on 127.0.0.1:4000
RUN printf '%s\n' \
  'server {' \
  '    listen 80;' \
  '    server_name _;' \
  '    root /usr/share/nginx/html;' \
  '    index index.html;' \
  '' \
  '    location / {' \
  '        try_files $uri $uri/ /index.html;' \
  '    }' \
  '' \
  '    location /api/ {' \
  '        proxy_pass http://127.0.0.1:4000;' \
  '        proxy_http_version 1.1;' \
  '        proxy_set_header Host $host;' \
  '        proxy_set_header X-Real-IP $remote_addr;' \
  '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
  '        proxy_set_header X-Forwarded-Proto $scheme;' \
  '    }' \
  '}' > /etc/nginx/http.d/default.conf

# Copy entire backend app + dependencies
WORKDIR /usr/src/app
COPY --from=backend-builder /app/server /usr/src/app

# Copy built frontend static assets
COPY --from=frontend-builder /app/client/dist /usr/share/nginx/html

# Environment defaults (secrets supplied at runtime)
ENV NODE_ENV=production \
    PORT=4000 \
    JWT_EXPIRES=7d \
    COOKIE_EXPIRE=7 \
    FRONTEND_URL=http://localhost

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/ || exit 1

CMD ["sh", "-c", "mkdir -p /run/nginx && (node /usr/src/app/server.js &) && nginx -g 'daemon off;'"]