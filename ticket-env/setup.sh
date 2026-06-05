#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  setup.sh — Inizializzazione ambiente ticket system su Podman
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── 1. Verifica prerequisiti ──────────────────────────────────────────────────
info "Verifica prerequisiti..."

command -v podman        >/dev/null 2>&1 || error "podman non trovato. Installa: sudo dnf install podman"
command -v podman-compose >/dev/null 2>&1 || {
  warn "podman-compose non trovato. Installo via pip..."
  pip3 install --user podman-compose || error "Impossibile installare podman-compose"
}

PODMAN_VERSION=$(podman --version | awk '{print $3}')
info "Podman versione: $PODMAN_VERSION"

# ── 2. Configura il socket Podman (necessario per podman-compose) ─────────────
info "Configuro socket Podman per l'utente corrente..."
systemctl --user enable --now podman.socket 2>/dev/null || \
  warn "Impossibile abilitare podman.socket (potrebbe essere già attivo)"

# Esporta DOCKER_HOST per podman-compose
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/podman/podman.sock"
info "DOCKER_HOST=$DOCKER_HOST"

# ── 3. Crea la struttura app di esempio (se non esiste) ───────────────────────
if [ ! -f "./app/go.mod" ]; then
  info "Creo struttura base dell'app Go..."
  mkdir -p app/cmd/server app/internal app/ent/schema
  cat > app/go.mod << 'GOMOD'
module github.com/yourorg/ticket-service

go 1.22

require (
	entgo.io/ent v0.14.0
	github.com/gin-gonic/gin v1.10.0
	github.com/golang-jwt/jwt/v5 v5.2.1
	github.com/google/uuid v1.6.0
	github.com/lib/pq v1.10.9
	github.com/MicahParks/keyfunc/v3 v3.3.0
)
GOMOD

  cat > app/cmd/server/main.go << 'GOSERVER'
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

func main() {
	port := os.Getenv("SERVER_PORT")
	if port == "" {
		port = "3000"
	}

	r := gin.Default()
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok", "service": "ticket-service"})
	})

	log.Printf("Ticket service in ascolto su :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}
GOSERVER
  info "Struttura app creata. Esegui 'cd app && go mod tidy' per scaricare le dipendenze."
fi

# ── 4. Avvia i servizi ────────────────────────────────────────────────────────
info "Avvio i servizi con podman-compose..."
podman-compose -f podman-compose.yml up -d postgres keycloak adminer

# ── 5. Attendi PostgreSQL ─────────────────────────────────────────────────────
info "Attendo PostgreSQL..."
MAX=30; COUNT=0
until podman exec ticket-postgres pg_isready -U ticket -d ticketdb 2>/dev/null; do
  sleep 3
  COUNT=$((COUNT+1))
  [ $COUNT -ge $MAX ] && error "PostgreSQL non si avvia. Controlla: podman logs ticket-postgres"
  echo -n "."
done
echo ""
info "PostgreSQL pronto."

# ── 6. Attendi Keycloak ───────────────────────────────────────────────────────
info "Attendo Keycloak (può richiedere 1-2 minuti al primo avvio)..."
MAX=60; COUNT=0
until curl -sf http://localhost:8080/health/ready >/dev/null 2>&1; do
  sleep 5
  COUNT=$((COUNT+1))
  [ $COUNT -ge $MAX ] && error "Keycloak non si avvia. Controlla: podman logs ticket-keycloak"
  echo -n "."
done
echo ""
info "Keycloak pronto."

# ── 7. Verifica realm importato ───────────────────────────────────────────────
info "Verifico importazione realm 'ticket'..."
ADMIN_TOKEN=$(curl -s -X POST "http://localhost:8080/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=admin_secret" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null)

if [ -z "$ADMIN_TOKEN" ]; then
  warn "Impossibile ottenere token admin. Verifica manualmente su http://localhost:8080"
else
  REALM_CHECK=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    "http://localhost:8080/admin/realms/ticket")
  if [ "$REALM_CHECK" = "200" ]; then
    info "Realm 'ticket' importato correttamente."
  else
    warn "Realm non trovato (HTTP $REALM_CHECK). Potrebbe ancora essere in fase di import."
  fi
fi

# ── 8. Test login utente di esempio ───────────────────────────────────────────
info "Test login con daniele1..."
LOGIN_RESP=$(curl -s -X POST "http://localhost:8080/realms/ticket/protocol/openid-connect/token" \
  -d "grant_type=password&client_id=ticket-service&client_secret=ticket-service-secret&username=daniele1&password=Password1!")
ACCESS_TOKEN=$(echo "$LOGIN_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('access_token','ERROR')[:40]+'...')" 2>/dev/null || echo "errore parsing")

if [[ "$ACCESS_TOKEN" == "ERROR"* ]] || [[ "$ACCESS_TOKEN" == "errore"* ]]; then
  warn "Login daniele1 non riuscito. Il realm potrebbe ancora essere in import."
else
  info "Login daniele1 OK — token: $ACCESS_TOKEN"
fi

# ── 9. Riepilogo ──────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Ambiente avviato con successo!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Servizi attivi:"
echo "    PostgreSQL  → localhost:5432  (user: ticket / ticket_secret)"
echo "    Keycloak    → http://localhost:8080  (admin / admin_secret)"
echo "    Adminer     → http://localhost:8081"
echo "    App Go      → http://localhost:3000  (se avviata)"
echo ""
echo "  Utenti demo (password: Password1!):"
echo "    daniele1     — customer (azienda acme)"
echo "    davide1      — customer (azienda acme)"
echo "    filippo1     — customer (azienda pippo)"
echo "    supportl1    — support_l1"
echo "    supportl2    — support_l2"
echo "    supervisor1  — supervisor"
echo ""
echo "  Comandi utili:"
echo "    make logs           → segui tutti i log"
echo "    make kc-token-user USER=daniele1 PASS=Password1!"
echo "    make api-test-daniele"
echo "    make db-shell"
echo ""
echo "  Avvia l'app Go:"
echo "    make infra-up && make run-local"
echo ""

# Esporta DOCKER_HOST nel profilo se non già presente
if ! grep -q 'DOCKER_HOST.*podman' ~/.bashrc 2>/dev/null; then
  echo "" >> ~/.bashrc
  echo "# Podman socket per podman-compose" >> ~/.bashrc
  echo 'export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"' >> ~/.bashrc
  info "Aggiunto DOCKER_HOST in ~/.bashrc"
fi
