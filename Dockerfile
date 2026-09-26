# ==============================================================================
# STAGE 1: Frontend Builder (Vite/React SPA)
# ==============================================================================
FROM node:20-alpine AS frontend-builder

WORKDIR /app/client

# Cache dependency layer first
COPY client/package.json ./

RUN npm install --legacy-peer-deps

# Copy frontend source and build production assets
COPY client/ ./

RUN npm run build

# ==============================================================================
# STAGE 2: Backend Builder (Express API)
# ==============================================================================
FROM node:20-alpine AS backend-builder

# Build toolchain required for native modules (bcrypt)
RUN apk add --no-cache python3 make g++

WORKDIR /app/server

# Cache dependency layer first
COPY server/package.json ./

RUN npm install --omit=dev --legacy-peer-deps

# Copy the ENTIRE backend application (routes, models, controllers, middlewares, utils)
COPY server/ ./

# ==============================================================================
# STAGE 3: Unified Production Runtime (Nginx + Node)
# ==============================================================================
FROM node:20-alpine AS runtime

# Install Nginx and prepare Alpine-specific runtime directories
RUN apk add --no-cache nginx \
    && mkdir -p /run/nginx /etc/nginx/http.d /etc/nginx/conf.d /usr/src/app /usr/share/nginx/html

# --- Backend runtime artifacts ---
WORKDIR /usr/src/app
COPY --from=backend-builder /app/server ./

# --- Frontend static artifacts ---
COPY --from=frontend-builder /app/client/dist /usr/share/nginx/html

# --- Nginx configuration: SPA fallback on :80, API reverse proxy to Node :4000 ---
RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
\n\
    client_max_body_size 10m;\n\
\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
\n\
    location /api/ {\n\
        proxy_pass http://127.0.0.1:4000;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Host $host;\n\
        proxy_set_header X-Real-IP $remote_addr;\n\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto $scheme;\n\
        proxy_set_header Cookie $http_cookie;\n\
    }\n\
\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
}\n' > /etc/nginx/http.d/default.conf

# Runtime environment configuration
ENV NODE_ENV=production \
    PORT=4000 \
    COOKIE_EXPIRE=5 \
    JWT_EXPIRES=5d \
    FRONTEND_URL=http://localhost \
    MONGO_URI="" \
    JWT_SECRET_KEY="" \
    CLOUDINARY_CLIENT_NAME="" \
    CLOUDINARY_CLIENT_API="" \
    CLOUDINARY_CLIENT_SECRET=""

EXPOSE 80

# Start Node backend in the background; Nginx in the foreground
CMD ["sh", "-c", "mkdir -p /run/nginx /tmp && (cd /usr/src/app && node server.js &) && nginx -g 'daemon off;'"]