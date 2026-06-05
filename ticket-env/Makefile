# ─────────────────────────────────────────────────────────────────────────────
#  Ticket System — Makefile (Podman)
# ─────────────────────────────────────────────────────────────────────────────
COMPOSE      := podman-compose
COMPOSE_FILE := podman-compose.yml
APP_DIR      := ./app

KC_URL       := http://localhost:8080
KC_REALM     := ticket
KC_ADMIN     := admin
KC_PASS      := admin_secret
KC_CLIENT    := ticket-service
KC_SECRET    := ticket-service-secret

.DEFAULT_GOAL := help

# ── Infrastruttura ────────────────────────────────────────────────────────────

.PHONY: up
up: ## Avvia tutti i servizi
	$(COMPOSE) -f $(COMPOSE_FILE) up -d

.PHONY: down
down: ## Ferma e rimuove i container
	$(COMPOSE) -f $(COMPOSE_FILE) down

.PHONY: down-volumes
down-volumes: ## Ferma e rimuove container + volumi (reset completo)
	$(COMPOSE) -f $(COMPOSE_FILE) down -v

.PHONY: restart
restart: down up ## Restart completo

.PHONY: ps
ps: ## Stato dei container
	$(COMPOSE) -f $(COMPOSE_FILE) ps

.PHONY: logs
logs: ## Segui i log di tutti i servizi
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f

.PHONY: logs-app
logs-app: ## Log solo dell'app Go
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f app

.PHONY: logs-kc
logs-kc: ## Log solo di Keycloak
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f keycloak

.PHONY: logs-db
logs-db: ## Log solo di PostgreSQL
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f postgres

# ── Build ─────────────────────────────────────────────────────────────────────

.PHONY: build
build: ## Build dell'immagine app
	$(COMPOSE) -f $(COMPOSE_FILE) build app

.PHONY: build-nc
build-nc: ## Build senza cache
	$(COMPOSE) -f $(COMPOSE_FILE) build --no-cache app

.PHONY: rebuild
rebuild: build ## Rebuild e restart solo dell'app
	$(COMPOSE) -f $(COMPOSE_FILE) up -d --force-recreate app

# ── Sviluppo locale (senza container app) ────────────────────────────────────

.PHONY: infra-up
infra-up: ## Avvia solo postgres e keycloak (sviluppo locale)
	$(COMPOSE) -f $(COMPOSE_FILE) up -d postgres keycloak adminer

.PHONY: run-local
run-local: ## Esegui l'app in locale (richiede infra-up)
	cd $(APP_DIR) && \
	DATABASE_URL="postgres://ticket:ticket_secret@localhost:5432/ticketdb?sslmode=disable" \
	KEYCLOAK_URL="http://localhost:8080" \
	KEYCLOAK_REALM="$(KC_REALM)" \
	KEYCLOAK_CLIENT_ID="$(KC_CLIENT)" \
	KEYCLOAK_CLIENT_SECRET="$(KC_SECRET)" \
	SERVER_PORT=3000 \
	GIN_MODE=debug \
	go run ./cmd/server

.PHONY: ent-gen
ent-gen: ## Genera codice Ent dagli schema
	cd $(APP_DIR) && go generate ./ent/...

.PHONY: test
test: ## Esegui i test
	cd $(APP_DIR) && go test ./... -v

.PHONY: lint
lint: ## Lint con golangci-lint
	cd $(APP_DIR) && golangci-lint run ./...

# ── Database ──────────────────────────────────────────────────────────────────

.PHONY: db-shell
db-shell: ## Apri psql nel container postgres
	podman exec -it ticket-postgres psql -U ticket -d ticketdb

.PHONY: db-dump
db-dump: ## Dump del database in ./backup.sql
	podman exec ticket-postgres pg_dump -U ticket ticketdb > backup.sql
	@echo "Dump salvato in backup.sql"

.PHONY: db-restore
db-restore: ## Ripristina da ./backup.sql
	podman exec -i ticket-postgres psql -U ticket ticketdb < backup.sql

# ── Keycloak ──────────────────────────────────────────────────────────────────

.PHONY: kc-token-admin
kc-token-admin: ## Ottieni token admin Keycloak
	@curl -s -X POST "$(KC_URL)/realms/master/protocol/openid-connect/token" \
	  -d "grant_type=password" \
	  -d "client_id=admin-cli" \
	  -d "username=$(KC_ADMIN)" \
	  -d "password=$(KC_PASS)" | python3 -m json.tool

.PHONY: kc-token-user
kc-token-user: ## Ottieni token utente (usa: make kc-token-user USER=daniele1 PASS=Password1!)
	@curl -s -X POST "$(KC_URL)/realms/$(KC_REALM)/protocol/openid-connect/token" \
	  -d "grant_type=password" \
	  -d "client_id=$(KC_CLIENT)" \
	  -d "client_secret=$(KC_SECRET)" \
	  -d "username=$(USER)" \
	  -d "password=$(PASS)" | python3 -m json.tool

.PHONY: kc-users
kc-users: ## Lista utenti nel realm ticket (richiede token admin)
	@ADMIN_TOKEN=$$(curl -s -X POST "$(KC_URL)/realms/master/protocol/openid-connect/token" \
	  -d "grant_type=password&client_id=admin-cli&username=$(KC_ADMIN)&password=$(KC_PASS)" \
	  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])") && \
	curl -s -H "Authorization: Bearer $$ADMIN_TOKEN" \
	  "$(KC_URL)/admin/realms/$(KC_REALM)/users" | python3 -m json.tool

# ── Test API ──────────────────────────────────────────────────────────────────

.PHONY: api-health
api-health: ## Controlla health dell'app
	@curl -s http://localhost:3000/health | python3 -m json.tool

.PHONY: api-test-daniele
api-test-daniele: ## Login come daniele1 e lista ticket
	@echo "=== Login daniele1 ==="
	@TOKEN=$$(curl -s -X POST "$(KC_URL)/realms/$(KC_REALM)/protocol/openid-connect/token" \
	  -d "grant_type=password&client_id=$(KC_CLIENT)&client_secret=$(KC_SECRET)&username=daniele1&password=Password1!" \
	  | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])") && \
	echo "=== GET /api/v1/tickets ===" && \
	curl -s -H "Authorization: Bearer $$TOKEN" http://localhost:3000/api/v1/tickets | python3 -m json.tool

# ── Utilità ───────────────────────────────────────────────────────────────────

.PHONY: wait-ready
wait-ready: ## Attendi che tutti i servizi siano healthy
	@echo "Attendo PostgreSQL..."
	@until podman exec ticket-postgres pg_isready -U ticket -d ticketdb 2>/dev/null; do sleep 2; done
	@echo "PostgreSQL pronto."
	@echo "Attendo Keycloak..."
	@until curl -sf http://localhost:8080/health/ready 2>/dev/null; do sleep 5; done
	@echo "Keycloak pronto."
	@echo "Tutti i servizi sono pronti!"

.PHONY: clean
clean: down-volumes ## Rimuove container, volumi e immagini buildate
	podman rmi ticket-env-app 2>/dev/null || true
	podman rmi ticket-env_app 2>/dev/null || true

.PHONY: status
status: ## Mostra stato dettagliato
	@echo "=== Container ===" && $(COMPOSE) -f $(COMPOSE_FILE) ps
	@echo "\n=== Porte ===" && podman port --all 2>/dev/null || true

.PHONY: help
help: ## Mostra questo help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' | sort

# ── Frontend ──────────────────────────────────────────────────────────────────

.PHONY: build-frontend
build-frontend: ## Build immagine frontend Angular
	$(COMPOSE) -f $(COMPOSE_FILE) build frontend

.PHONY: rebuild-frontend
rebuild-frontend: ## Rebuild e restart frontend (dopo modifiche al codice)
	$(COMPOSE) -f $(COMPOSE_FILE) build --no-cache frontend
	$(COMPOSE) -f $(COMPOSE_FILE) up -d --force-recreate frontend

.PHONY: logs-frontend
logs-frontend: ## Log del container frontend
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f frontend

.PHONY: up-full
up-full: ## Avvia TUTTI i servizi incluso frontend
	$(COMPOSE) -f $(COMPOSE_FILE) up -d
	@echo ""
	@echo "  Servizi attivi:"
	@echo "    Frontend  → http://localhost:4200"
	@echo "    Backend   → http://localhost:3000"
	@echo "    Keycloak  → http://localhost:8080"
	@echo "    Adminer   → http://localhost:8081"
