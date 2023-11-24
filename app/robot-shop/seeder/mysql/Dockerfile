FROM debian:trixie-slim

ENV MYSQL_HOST="localhost"
ENV MYSQL_PORT="5506"
ENV MYSQL_USER="<defaults>"
ENV MYSQL_PASSWORD="<defaults>"
ENV MYSQL_DATABASE="<default>"

## Add the wait script to the image
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/2.7.3/wait /wait

COPY ../seeds/* /opt/seeds/
COPY --chmod=775 ../bin/seeder.sh /opt/seeds/seeder.sh

RUN mkdir -p /usr/share/man/man1 /usr/share/man/man2 \
    && apt-get update \
    && apt-get install -y \
      software-properties-common \
      gnupg2 \
      apt-transport-https \
      apt-utils \
      ca-certificates \
      bash \
      mariadb-client \
      curl \
    && chmod +x /wait