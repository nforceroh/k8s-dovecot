FROM ghcr.io/nforceroh/k8s-alpine-baseimage:latest

ARG \
  BUILD_DATE=now \
  VERSION=unknown

LABEL \
  maintainer="Sylvain Martin (sylvain@nforcer.com)" 

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
	DEBUG=0
	
RUN \
	echo "Add vmail and dovecot users" \
	&& addgroup -g 5000 vmail \
  && addgroup -g 401 dovecot \
  && addgroup -g 402 dovenull \
  && adduser -D -u 5000 -G vmail -h /var/vmail vmail \
  && adduser -D -G dovecot -u 401 -h /dev/null -s /sbin/nologin dovecot \
  && adduser -D -G dovenull -u 402 -h /dev/null -s /sbin/nologin dovenull \
	&& echo "Installing Dovecot" \
	&& apk add --no-cache --update \
		bash \
		bind-tools \
		findutils \
		envsubst \
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

### Add Files
ADD /content/configfiles /configfiles
ADD /content/etc /etc
ADD --chmod=755 /content/usr /usr
ADD --chmod=755 /content/s6-overlay /etc/s6-overlay

# dovecot
#   24 ltmp, 110 pop3, 143 imap, 993 imaps, 3333 doveadm, 4190 sieve, 12345 sasl
EXPOSE 24 110 143 993 3333 4190 12345

#Adding volumes
VOLUME ["/data"]
ENTRYPOINT [ "/init" ]
