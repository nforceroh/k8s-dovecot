FROM ghcr.io/nforceroh/k8s-alpine-baseimage:3.23

ARG \
  BUILD_DATE=unknown \
  VERSION=unknown

LABEL \
  org.label-schema.maintainer="Sylvain Martin (sylvain@nforcer.com)" \
  org.label-schema.build-date="${BUILD_DATE}" \
  org.label-schema.version="${VERSION}" \
  org.label-schema.vcs-url="https://github.com/nforcer/k8s-dovecot" \
  org.label-schema.schema-version="1.0"

ENV \
	LANG=C.UTF-8 \
	LC_ALL=C.UTF-8 \
	UMASK=000 \
	PUID=3001 \
	PGID=3000 \
	TZ=America/New_York \
	DB_HOST=mariadb \
	DB_PORT=3306 \
	DB_NAME=mail \
	DB_USER=user \
	DB_PASS=password \
	VMAIL_UID=5000 \
	VMAIL_GID=12 \
  FQDN=mail.example.com \
	RSPAMD_HOST=rspamd-svc \
	SKIP_FTS=n \
	DEBUG=0
	
# Create vmail and dovecot users
RUN \
	echo "Add vmail and dovecot users" \
	&& addgroup -g 5000 vmail \
	&& addgroup -g 401 dovecot \
	&& addgroup -g 402 dovenull \
	&& adduser -D -u 5000 -G vmail -h /var/vmail vmail \
	&& adduser -D -G dovecot -u 401 -h /dev/null -s /sbin/nologin dovecot \
	&& adduser -D -G dovenull -u 402 -h /dev/null -s /sbin/nologin dovenull

# Install build dependencies and runtime packages
RUN apk add --no-cache --update \
	bash \
	bind-tools \
	findutils \
	ca-certificates \
	curl \
	coreutils \
	jq \
	icu-data-full \
	mariadb-connector-c \
	mariadb-dev \
	glib-dev \
	gcompat \
	mariadb-client \
	procps \
	python3 \
	py3-mysqlclient \
	py3-html2text \
	py3-jinja2 \
	py3-redis \
	tzdata \
	wget \
	netcat-openbsd \
	dovecot \
	dovecot-dev \
	dovecot-lmtpd \
	dovecot-lua \
	dovecot-ldap \
	dovecot-mysql \
	dovecot-sql \
	dovecot-submissiond \
	dovecot-pigeonhole-plugin \
	dovecot-pop3d \
	dovecot-fts-flatcurve

# Clean up build dependencies
RUN apk del --no-cache \
	mariadb-dev \
	glib-dev \
	dovecot-dev \
	&& rm -rf /var/cache/apk/*

# Copy configuration and service files
COPY /content/configfiles /configfiles
COPY /content/etc /etc
COPY --chmod=755 /content/usr /usr
COPY --chmod=755 /content/s6-overlay /etc/s6-overlay

# dovecot ports:
#   24 lmtp, 110 pop3, 143 imap, 993 imaps, 3333 doveadm, 4190 sieve, 12345 sasl
EXPOSE 24 110 143 993 3333 4190 12345

# Health check - verify IMAP port is listening
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD nc -z localhost 143 || exit 1

# Data volume for mail storage and sieve scripts
VOLUME ["/data"]

ENTRYPOINT [ "/init" ]
