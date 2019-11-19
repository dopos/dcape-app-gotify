# dcape-app-gotify Makefile

SHELL          = /bin/bash
CFG           ?= .env
PRG           ?= $(shell basename $$PWD)

# -----------------------------------------------------------------------------
# Runtime data

# Site host
APP_SITE      ?= $(PRG).dev.lan

# Admin user name
ADMIN_USER        ?= admin
# Admin password
ADMIN_PASS    ?= $(shell < /dev/urandom tr -dc A-Za-z0-9 | head -c14; echo)

# Database name
PGDATABASE    ?= $(PRG)
# Database user name
PGUSER        ?= $(PRG)
# Database user password
PGPASSWORD    ?= $(shell < /dev/urandom tr -dc A-Za-z0-9 | head -c14; echo)
# Database host
PGHOST        = db

PGSSLMODE     ?= disable
PGAPPNAME     ?= $(PRG)

# -----------------------------------------------------------------------------
# Docker

# Docker image name
IMAGE         ?= gotify/server
# Docker image tag
IMAGE_VER     ?= 2.0.11

# dcape container name prefix
DCAPE_PROJECT_NAME ?= dcape
# dcape network attach to
DCAPE_NET          ?= $(DCAPE_PROJECT_NAME)_default
# dcape postgresql container name
DCAPE_DB           ?= $(DCAPE_PROJECT_NAME)_db_1

# Docker-compose image tag
DC_VER             ?= 1.23.2

define CONFIG_DEF
# ------------------------------------------------------------------------------
# Gotify settings

# Site host
APP_SITE=$(APP_SITE)

# Admin user name
ADMIN_USER=$(ADMIN_USER)
# Admin password
ADMIN_PASS=$(ADMIN_PASS)

PGDATABASE=$(PGDATABASE)
PGUSER=$(PGUSER)
PGPASSWORD=$(PGPASSWORD)
PGHOST=$(PGHOST)

# Docker details

# Docker image name
IMAGE=$(IMAGE)
# Docker image tag
IMAGE_VER=$(IMAGE_VER)

PGSSLMODE=$(PGSSLMODE)
DCAPE_NET=$(DCAPE_NET)

endef
export CONFIG_DEF

-include $(CFG)
export

.PHONY: all $(CFG) setup start stop up reup down docker-wait db-create db-drop psql dc help

all: help

# ------------------------------------------------------------------------------
# webhook commands

start: db-create up

start-hook: db-create reup

stop: down

update: reup

# ------------------------------------------------------------------------------
# docker commands

## старт контейнеров
up:
up: CMD=up -d
up: dc

## рестарт контейнеров
reup:
reup: CMD=up --force-recreate -d
reup: dc

## остановка и удаление всех контейнеров
down:
down: CMD=rm -f -s
down: dc


# Wait for postgresql container start
docker-wait:
	@echo -n "Checking PG is ready..."
	@until [[ `docker inspect -f "{{.State.Health.Status}}" $$DCAPE_DB` == healthy ]] ; do sleep 1 ; echo -n "." ; done
	@echo "Ok"

# ------------------------------------------------------------------------------
# DB operations

# create user, db and load sql
db-create: docker-wait
	@echo "*** $@ ***" ; \
	docker exec -i $$DCAPE_DB psql -U postgres -c "CREATE USER \"$$PGUSER\" WITH PASSWORD '$$PGPASSWORD';" || true ; \
	docker exec -i $$DCAPE_DB psql -U postgres -c "CREATE DATABASE \"$$PGDATABASE\" OWNER \"$$PGUSER\";" || db_exists=1

## drop database and user
db-drop: docker-wait
	@echo "*** $@ ***"
	@docker exec -it $$DCAPE_DB psql -U postgres -c "DROP DATABASE \"$$PGDATABASE\";" || true
	@docker exec -it $$DCAPE_DB psql -U postgres -c "DROP USER \"$$PGUSER\";" || true

psql: docker-wait
	@docker exec -it $$DCAPE_DB psql -U $$PGUSER -d $$PGDATABASE

# ------------------------------------------------------------------------------

# $$PWD используется для того, чтобы текущий каталог был доступен в контейнере по тому же пути
# и относительные тома новых контейнеров могли его использовать
## run docker-compose
dc: docker-compose.yml
	@docker run --rm  \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  -v $$PWD:$$PWD \
	  -w $$PWD \
	  docker/compose:$(DC_VER) \
	  -p $$PRG \
	  $(CMD)

# ------------------------------------------------------------------------------

$(CFG):
	@[ -f $@ ] || { echo "$$CONFIG_DEF" > $@ ; echo "Warning: Created default $@" ; }

# ------------------------------------------------------------------------------

## List Makefile targets
help:
	@grep -A 1 "^##" Makefile | less

##
## Press 'q' for exit
##
