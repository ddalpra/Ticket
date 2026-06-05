# ── Stage 1: build Angular ────────────────────────────────────────────────────
FROM docker.io/node:20-alpine AS builder

WORKDIR /app

# Copia prima solo i file di dipendenze per sfruttare la cache layer
COPY package.json package-lock.json* ./
RUN npm install --legacy-peer-deps --silent

# Copia i sorgenti e compila in produzione
COPY . .
RUN npm run build

# ── Stage 2: runtime Nginx ────────────────────────────────────────────────────
FROM docker.io/nginx:1.25-alpine

# Copia la build Angular (Angular 18 mette l'output in browser/)
COPY --from=builder /app/dist/ticket-ui-fresh/browser /usr/share/nginx/html

# Configurazione Nginx: SPA routing + proxy API verso il backend Go
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost/ || exit 1
