-- Crea schema separato per Keycloak (evita collisioni con le tabelle applicative)
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Estensione UUID
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Grant permessi a keycloak schema
GRANT ALL PRIVILEGES ON SCHEMA keycloak TO ticket;
