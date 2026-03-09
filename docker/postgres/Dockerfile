FROM postgres:16

ENV POSTGRES_DB=deebee
ENV POSTGRES_USER=deebee
ENV POSTGRES_PASSWORD=deebee

COPY docker/postgres/initdb/ /docker-entrypoint-initdb.d/
