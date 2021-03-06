FROM node:12.16-slim as builder

ARG STANDALONE

RUN mkdir /opt/local && apt-get update && apt-get install -y --no-install-recommends git gpg dirmngr ca-certificates wget \
    $([ -n "$STANDALONE" ] || echo "autoconf automake build-essential gettext libtool libgmp-dev \
                                     libsqlite3-dev python python3 python3-mako zlib1g-dev")

ARG TESTRUNNER

ENV LIGHTNINGD_VERSION=v0.8.2.1
ENV LIGHTNINGD_PGP_KEY=15EE8D6CAB0E7F0CF999BFCBD9200E6CD1ADB8F1

RUN [ -n "$STANDALONE" ] || \
    (git clone https://github.com/ElementsProject/lightning.git /opt/lightningd \
    && cd /opt/lightningd \
    && gpg --keyserver keyserver.ubuntu.com --recv-keys "$LIGHTNINGD_PGP_KEY" \
    && git verify-tag $LIGHTNINGD_VERSION \
    && git checkout $LIGHTNINGD_VERSION \
    && DEVELOPER=$TESTRUNNER ./configure --prefix=./target \
    && make \
    && make install \
    && rm -r target/share \
    && mv -f target/* /opt/local/)

ENV BITCOIN_VERSION 0.20.0
ENV BITCOIN_FILENAME bitcoin-$BITCOIN_VERSION-x86_64-linux-gnu.tar.gz
ENV BITCOIN_URL https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/$BITCOIN_FILENAME
ENV BITCOIN_SHA256 35ec10f87b6bc1e44fd9cd1157e5dfa483eaf14d7d9a9c274774539e7824c427
ENV BITCOIN_ASC_URL https://bitcoincore.org/bin/bitcoin-core-$BITCOIN_VERSION/SHA256SUMS.asc
ENV BITCOIN_PGP_KEY 01EA5486DE18A882D4C2684590C8019E36C2E964
RUN [ -n "$STANDALONE" ] || \
    (mkdir /opt/bitcoin && cd /opt/bitcoin \
    && wget -qO "$BITCOIN_FILENAME" "$BITCOIN_URL" \
    && echo "$BITCOIN_SHA256 $BITCOIN_FILENAME" | sha256sum -c - \
    && gpg --keyserver keyserver.ubuntu.com --recv-keys "$BITCOIN_PGP_KEY" \
    && wget -qO bitcoin.asc "$BITCOIN_ASC_URL" \
    && gpg --verify bitcoin.asc \
    && cat bitcoin.asc | grep "$BITCOIN_FILENAME" | sha256sum -c - \
    && BD=bitcoin-$BITCOIN_VERSION/bin \
    && tar -xzvf "$BITCOIN_FILENAME" $BD/bitcoind $BD/bitcoin-cli --strip-components=1 \
    && mv bin/* /opt/local/bin/)

RUN wget -qO /usr/bin/tini "https://github.com/krallin/tini/releases/download/v0.19.0/tini-amd64" \
    && echo "93dcc18adc78c65a028a84799ecf8ad40c936fdfc5f2a57b1acda5a8117fa82c /usr/bin/tini" | sha256sum -c - \
    && chmod +x /usr/bin/tini

WORKDIR /opt/charged

COPY package.json npm-shrinkwrap.json ./
RUN npm install \
   && test -n "$TESTRUNNER" || { \
      cp -r node_modules node_modules.dev \
      && npm prune --production \
      && mv -f node_modules node_modules.prod \
      && mv -f node_modules.dev node_modules; }

COPY . .
RUN npm run dist \
    && rm -rf src \
    && test -n "$TESTRUNNER" || (rm -rf test node_modules && mv -f node_modules.prod node_modules)

FROM node:12.16-slim

WORKDIR /opt/charged
ARG TESTRUNNER
ENV HOME /tmp
ENV NODE_ENV production
ARG STANDALONE
ENV STANDALONE=$STANDALONE

RUN apt-get update \
    && apt-get install -y --no-install-recommends inotify-tools \
    && ([ -n "$STANDALONE" ] || apt-get install -y --no-install-recommends libgmp-dev libsqlite3-dev) \
    && ([ -z "$TESTRUNNER" ] || apt-get install -y --no-install-recommends jq procps curl) \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /opt/charged/bin/charged /usr/bin/charged \
    && mkdir /data \
    && ln -s /data/lightning /tmp/.lightning

COPY --from=builder /opt/local /usr/local
COPY --from=builder /opt/charged /opt/charged
COPY --from=builder /usr/bin/tini /usr/bin/

ENTRYPOINT [ "tini", "-g", "--", "bin/docker-entrypoint.sh" ]
EXPOSE 9112 9735
