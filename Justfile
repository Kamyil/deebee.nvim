set shell := ["bash", "-cu"]

image := "deebee-postgres:dev"
container := "deebee-postgres"
volume := "deebee-postgres-data"
port := "55432"
db := "deebee"
user := "deebee"
password := "deebee"

default:
    @just --list

pg-build:
    docker build -t {{image}} -f docker/postgres/Dockerfile .

pg-run: pg-build
    if docker container inspect {{container}} >/dev/null 2>&1; then docker rm -f {{container}}; fi
    docker volume create {{volume}} >/dev/null
    docker run -d --name {{container}} \
      -e POSTGRES_DB={{db}} \
      -e POSTGRES_USER={{user}} \
      -e POSTGRES_PASSWORD={{password}} \
      -p {{port}}:5432 \
      -v {{volume}}:/var/lib/postgresql/data \
      {{image}}
    just pg-wait
    @echo "Postgres ready at postgres://{{user}}:{{password}}@localhost:{{port}}/{{db}}"

pg-stop:
    if docker container inspect {{container}} >/dev/null 2>&1; then docker stop {{container}}; fi

pg-rm:
    if docker container inspect {{container}} >/dev/null 2>&1; then docker rm -f {{container}}; fi

pg-reset:
    if docker container inspect {{container}} >/dev/null 2>&1; then docker rm -f {{container}}; fi
    docker volume rm -f {{volume}} >/dev/null 2>&1 || true
    just pg-run

pg-wait:
    for i in {1..60}; do \
      status="$$(docker inspect -f '{{"{{.State.Status}}"}}' {{container}} 2>/dev/null || true)"; \
      if [ "$$status" = "exited" ] || [ "$$status" = "dead" ]; then \
        docker logs {{container}}; \
        exit 1; \
      fi; \
      if docker exec {{container}} pg_isready -U {{user}} -d {{db}} >/dev/null 2>&1; then \
        exit 0; \
      fi; \
      sleep 1; \
    done; \
    docker logs {{container}}; \
    exit 1

pg-logs:
    docker logs -f {{container}}

pg-status:
    docker ps --filter name={{container}}

pg-url:
    @echo "postgres://{{user}}:{{password}}@localhost:{{port}}/{{db}}"

pg-psql:
    docker exec -it {{container}} psql -U {{user}} -d {{db}}

pg-query sql="select current_database(), current_user;":
    docker exec {{container}} psql -U {{user}} -d {{db}} -c "{{sql}}"

pg-shell:
    docker exec -it {{container}} bash
