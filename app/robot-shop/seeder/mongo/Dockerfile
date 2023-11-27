# FROM mongo:7.0.3
FROM debian:trixie-slim

# COPY *.js /docker-entrypoint-initdb.d/
ENV NODE_MODULES=/usr/local/lib/node_modules
## Add the wait script to the image
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/2.7.3/wait /wait

COPY ./seeds/* /opt/seeds/
COPY --chmod=775 ./bin/seeder.sh /opt/seeds/seeder.sh

RUN mkdir -p /usr/share/man/man1 /usr/share/man/man2 \
    && apt-get update \
    && apt-get purge -y nodejs --auto-remove \
    && apt-get purge -y npm --auto-remove \
    && rm /usr/local/bin/node \
    && apt-get install -y \
      software-properties-common \
      gnupg2 \
      apt-transport-https \
      apt-utils \
      ca-certificates \
      bash \
      curl \
      nodejs \
      npm \
    && npm cache clean -f \
    && npm install -g n \ 
    && n stable \
    && npm install -g mongodb \
    && chmod +x /wait