# Ticket System — Ambiente di sviluppo (Podman)

## Prerequisiti

```bash
# Fedora / RHEL / CentOS
sudo dnf install podman python3-pip

# Ubuntu / Debian
sudo apt install podman python3-pip

# podman-compose (cross-distro)
pip3 install --user podman-compose
```

## Avvio rapido

```bash
chmod +x setup.sh
./setup.sh
```

Lo script avvia PostgreSQL e Keycloak, attende che siano healthy, e verifica l'importazione del realm.

## Struttura

```
ticket-env/
├── podman-compose.yml      # definizione servizi
├── .env                    # variabili d'ambiente
├── Makefile                # comandi operativi
├── setup.sh                # setup iniziale
├── postgres/
│   └── init.sql            # crea schema keycloak + estensione uuid
├── keycloak/
│   └── realm-export.json   # realm 'ticket' preconfigurato
└── app/
    └── Dockerfile          # build multi-stage Go
```

## Servizi

| Servizio   | URL / Host              | Credenziali                      |
|------------|-------------------------|----------------------------------|
| PostgreSQL | localhost:5432          | ticket / ticket_secret           |
| Keycloak   | http://localhost:8080   | admin / admin_secret             |
| Adminer    | http://localhost:8081   | server: postgres, db: ticketdb   |
| App Go     | http://localhost:3000   | —                                |

## Utenti Keycloak (password: `Password1!`)

| Username    | Ruolo       | Azienda |
|-------------|-------------|---------|
| daniele1    | customer    | acme    |
| davide1     | customer    | acme    |
| filippo1    | customer    | pippo   |
| supportl1   | support_l1  | —       |
| supportl2   | support_l2  | —       |
| supervisor1 | supervisor  | —       |

> Daniele1 e Davide1 appartengono alla stessa azienda e vedono gli stessi ticket.

## Comandi Makefile

```bash
make up              # avvia tutti i servizi
make down            # ferma i servizi
make infra-up        # solo postgres + keycloak + adminer (sviluppo locale)
make run-local       # esegui l'app Go in locale
make logs            # segui tutti i log
make logs-app        # log solo app
make db-shell        # psql interattivo
make wait-ready      # attendi che tutto sia healthy

# Token e API test
make kc-token-user USER=daniele1 PASS=Password1!
make api-test-daniele
make api-health

make help            # lista completa comandi
```

## Flusso sviluppo tipico

```bash
# 1. Avvia solo l'infrastruttura
make infra-up
make wait-ready

# 2. Sviluppa e testa l'app localmente
cd app
go generate ./ent/...
make run-local   # oppure: go run ./cmd/server

# 3. Ottieni token per testare le API
make kc-token-user USER=daniele1 PASS=Password1!

# 4. Usa il token per chiamare le API
curl -H "Authorization: Bearer <token>" http://localhost:3000/api/v1/tickets
```

## Gestione del socket Podman

`podman-compose` richiede il socket Podman attivo:

```bash
# Abilita il socket per l'utente corrente (rootless)
systemctl --user enable --now podman.socket

# Variabile d'ambiente necessaria
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
# setup.sh la aggiunge automaticamente a ~/.bashrc
```

## Reset completo

```bash
make down-volumes   # rimuove container e volumi
make clean          # rimuove anche le immagini buildate
./setup.sh          # riparte da zero
```

## Keycloak — Accesso admin

1. Apri http://localhost:8080
2. Accedi con `admin` / `admin_secret`
3. Seleziona il realm `ticket` dal menu in alto a sinistra
4. Utenti, ruoli e client sono già configurati da `realm-export.json`

## Note Podman vs Docker

- Podman è **rootless** by default — nessun demone root necessario
- `podman-compose` è compatibile con `docker-compose` v3
- I volumi sono in `~/.local/share/containers/storage/volumes/`
- Per usare comandi `docker` come alias: `alias docker=podman`
