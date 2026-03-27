.DEFAULT_GOAL := help

INFRA := infrastructure

-include $(INFRA)/.env
export

# ─── Entwicklung ────────────────────────────────────────────────────────────

.PHONY: up
up: ## Lokale Umgebung starten
	docker compose -f $(INFRA)/docker-compose.yml up -d

.PHONY: down
down: ## Lokale Umgebung stoppen
	docker compose -f $(INFRA)/docker-compose.yml down

.PHONY: logs
logs: ## Logs aller Services anzeigen
	docker compose -f $(INFRA)/docker-compose.yml logs -f

# ─── Build / Deploy ──────────────────────────────────────────────────────────

.PHONY: build
build: ## Docker Images bauen
	docker compose -f $(INFRA)/docker-compose.yml build

.PHONY: deploy
deploy: ## Auf Hetzner deployen (via Jenkins SSH)
	ssh hetzner "cd /app && git pull && make build && make db-migrate && docker compose -f $(INFRA)/docker-compose.yml up -d"

# ─── Code-Qualität ───────────────────────────────────────────────────────────

.PHONY: lint
lint: lint-frontend lint-backend ## Alle Linter ausführen (Frontend + Backend)

.PHONY: lint-frontend
lint-frontend: ## ESLint prüfen (Frontend)
	docker compose -f $(INFRA)/docker-compose.yml run --rm frontend npm run lint

.PHONY: lint-backend
lint-backend: ## ruff check (Backend)
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service ruff check .

.PHONY: format
format: format-frontend format-backend ## Alle Formatter ausführen

.PHONY: format-frontend
format-frontend: ## Prettier anwenden (Frontend)
	docker compose -f $(INFRA)/docker-compose.yml run --rm frontend npm run format

.PHONY: format-backend
format-backend: ## ruff format (Backend)
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service ruff format .

# ─── Testing ─────────────────────────────────────────────────────────────────

.PHONY: test
test: test-frontend test-backend ## Alle Tests ausführen

.PHONY: test-frontend
test-frontend: ## Vitest ausführen (Frontend)
	docker compose -f $(INFRA)/docker-compose.yml run --rm frontend npm run test

.PHONY: test-backend
test-backend: ## pytest ausführen (Backend)
	docker compose -f $(INFRA)/docker-compose.test.yml up --abort-on-container-exit --exit-code-from ai-service-test
	docker compose -f $(INFRA)/docker-compose.test.yml down --volumes

# ─── Datenbank ───────────────────────────────────────────────────────────────

.PHONY: db-migrate
db-migrate: ## Alle ausstehenden Migrationen ausführen
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service alembic upgrade head

.PHONY: db-migrate-create
db-migrate-create: ## Neue Migration erstellen — MSG="beschreibung" erforderlich
	@test -n "$(MSG)" || (echo "Fehler: MSG ist nicht gesetzt. Verwendung: make db-migrate-create MSG=\"beschreibung\"" && exit 1)
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service alembic revision --autogenerate -m "$(MSG)"

.PHONY: db-migrate-status
db-migrate-status: ## Aktuellen Migrationsstatus anzeigen
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service alembic current

.PHONY: db-rollback
db-rollback: ## Letzte Migration rückgängig machen
	docker compose -f $(INFRA)/docker-compose.yml run --rm ai-service alembic downgrade -1

.PHONY: db-seed
db-seed: ## Seed-Daten einspielen (infrastructure/database/seeds/)
ifdef FILE
	docker compose -f $(INFRA)/docker-compose.yml exec postgres psql -U $${POSTGRES_USER} -d $${POSTGRES_DB} -f /seeds/$(FILE).sql
else
	@for file in $(INFRA)/database/seeds/*.sql; do \
		echo "Importing $$file ..."; \
		docker compose -f $(INFRA)/docker-compose.yml exec -T postgres psql -U $${POSTGRES_USER} -d $${POSTGRES_DB} < $$file; \
	done
endif

.PHONY: db-reset
db-reset: ## DB zurücksetzen + Migrationen + Seed (nur lokal!)
	docker compose -f $(INFRA)/docker-compose.yml down -v
	docker compose -f $(INFRA)/docker-compose.yml up -d postgres
	@echo "Warte auf PostgreSQL ..."
	@sleep 5
	$(MAKE) db-migrate
	$(MAKE) db-seed

# ─── Backup ──────────────────────────────────────────────────────────────────

.PHONY: backup
backup: ## Vollständiges DB-Backup (Schema + Daten)
	@mkdir -p $(INFRA)/database/backups
	@TIMESTAMP=$$(date +%Y-%m-%d_%H%M%S) && \
	  docker compose -f $(INFRA)/docker-compose.yml exec postgres pg_dump \
	    -U $${POSTGRES_USER} \
	    -d $${POSTGRES_DB} \
	    --no-owner \
	    --no-acl \
	    -f /tmp/backup_$${TIMESTAMP}.sql && \
	  docker compose -f $(INFRA)/docker-compose.yml cp postgres:/tmp/backup_$${TIMESTAMP}.sql \
	    $(INFRA)/database/backups/$${TIMESTAMP}.sql && \
	  echo "Backup erstellt: $(INFRA)/database/backups/$${TIMESTAMP}.sql"

.PHONY: backup-schema
backup-schema: ## Nur Schema sichern (ohne Daten)
	@mkdir -p $(INFRA)/database/backups
	@TIMESTAMP=$$(date +%Y-%m-%d_%H%M%S) && \
	  docker compose -f $(INFRA)/docker-compose.yml exec postgres pg_dump \
	    -U $${POSTGRES_USER} \
	    -d $${POSTGRES_DB} \
	    --no-owner \
	    --no-acl \
	    --schema-only \
	    -f /tmp/schema_$${TIMESTAMP}.sql && \
	  docker compose -f $(INFRA)/docker-compose.yml cp postgres:/tmp/schema_$${TIMESTAMP}.sql \
	    $(INFRA)/database/backups/schema_$${TIMESTAMP}.sql && \
	  echo "Schema-Backup erstellt: $(INFRA)/database/backups/schema_$${TIMESTAMP}.sql"

.PHONY: backup-restore
backup-restore: ## Backup wiederherstellen — FILE=infrastructure/database/backups/<datei>.sql erforderlich
	@test -n "$(FILE)" || (echo "Fehler: FILE ist nicht gesetzt. Verwendung: make backup-restore FILE=$(INFRA)/database/backups/<datei>.sql" && exit 1)
	docker compose -f $(INFRA)/docker-compose.yml exec -T postgres psql \
	  -U $${POSTGRES_USER} \
	  -d $${POSTGRES_DB} < $(FILE)

.PHONY: backup-remote
backup-remote: ## Backup von Hetzner holen (SSH + SCP)
	ssh hetzner "cd /app && make backup"
	scp hetzner:/app/$(INFRA)/database/backups/$$(ssh hetzner "ls -t /app/$(INFRA)/database/backups | head -1") \
	  $(INFRA)/database/backups/

# ─── Hilfe ───────────────────────────────────────────────────────────────────

.PHONY: help
help: ## Alle verfügbaren Befehle anzeigen
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'
