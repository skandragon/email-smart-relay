#!/bin/bash

[ "${DEBUG}" == "yes" ] && set -x

function set_config() {
  local key=${1}
  local value=${2}
  [ -z "${key}" ] && echo "ERROR: key is empty" && exit 1
  [ -z "${value}" ] && echo "ERROR: value is empty" && exit 1

  echo "Setting configuration option ${key} with value: ${value}"
  postconf -e "${key} = ${value}"
}

[ -z "${SMTP_SERVER}" ] && echo "ERROR: SMTP_SERVER is empty" && exit 1
[ -z "${SERVER_HOSTNAME}" ] && echo "ERROR: SERVER_HOSTNAME is empty" && exit 1
[ ! -z "${SMTP_USERNAME}" -a -z "${SMTP_PASSWORD}" ] && echo "SMTP_USERNAME is set but SMTP_PASSWORD is empty" && exit 1

# Default to submission port to avoid ISP blocking of outgoing port 25
SMTP_PORT="${SMTP_PORT:-587}"

# Strip off hostname and use it as the domain
DOMAIN=`echo ${SERVER_HOSTNAME} | awk 'BEGIN{FS=OFS="."}{print $(NF-1),$NF}'`

set_config "maillog_file" "/dev/stdout"
set_config "myhostname" ${SERVER_HOSTNAME}
set_config "mydomain" ${DOMAIN}
set_config "mydestination" "${DESTINATION:-localhost}"
set_config "myorigin" '$mydomain'
set_config "relayhost" "[${SMTP_SERVER}]:${SMTP_PORT}"
set_config "smtp_use_tls" "yes"
if [ ! -z "${SMTP_USERNAME}" ]; then
  set_config "smtp_sasl_auth_enable" "yes"
  set_config "smtp_sasl_password_maps" "lmdb:/etc/postfix/sasl_passwd"
  set_config "smtp_sasl_security_options" "noanonymous"
fi
set_config "always_add_missing_headers" "${ALWAYS_ADD_MISSING_HEADERS:-no}"
set_config "smtp_host_lookup" "native,dns"
set_config "inet_protocols" "all"

# Create sasl_passwd file unless one is provided via volume mount
if [ ! -f /etc/postfix/sasl_passwd -a ! -z "${SMTP_USERNAME}" ]; then
  grep -q "${SMTP_SERVER}" /etc/postfix/sasl_passwd  > /dev/null 2>&1
  if [ $? -gt 0 ]; then
    echo "Setting SASL SMTP credentials"
    echo "[${SMTP_SERVER}]:${SMTP_PORT} ${SMTP_USERNAME}:${SMTP_PASSWORD}" >> /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd
  fi
fi

if [ ! -z "${SMTP_HEADER_TAG}" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_checks"
  echo -e "/^MIME-Version:/i PREPEND RelayTag: ${SMTP_HEADER_TAG}\n/^Content-Transfer-Encoding:/i PREPEND RelayTag: $SMTP_HEADER_TAG" >> /etc/postfix/header_checks
  echo "Outgoing email will be tagged with SMTP_HEADER_TAG: ${SMTP_HEADER_TAG}"
fi

if [ "${LOG_SUBJECT}" == "yes" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_checks"
  echo -e "/^Subject:/ WARN" >> /etc/postfix/header_checks
  echo "Enabling logging of subject line"
fi

# set allowed incoming networks
nets='10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16'
if [ ! -z "${SMTP_NETWORKS}" ]; then
  declare re="^((([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|\
    ([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|\
    ([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|\
    ([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|\
    :((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}|\
    ::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|\
    (2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|\
    (2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))/[0-9]{1,3})$"

  for i in $(sed 's/,/\ /g' <<<$SMTP_NETWORKS); do
    if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
      nets+=", $i"
    elif grep -Eq "$re" <<<$i ; then
      readarray -d \/ -t arr < <(printf '%s' "$i")
      nets+=", [${arr[0]}]/${arr[1]}"
    else
      echo "$i is not a valid IPv4 or IPv6 address."
      exit 1
    fi
  done
fi
set_config "mynetworks" "${nets}"

if [ ! -z "${OVERWRITE_FROM}" ]; then
  echo -e "/^From:.*$/ REPLACE From: $OVERWRITE_FROM" > /etc/postfix/smtp_header_checks
  postmap /etc/postfix/smtp_header_checks
  postconf -e 'smtp_header_checks = regexp:/etc/postfix/smtp_header_checks'
  echo "Overwriting From with OVERWRITE_FROM: ${OVERWRITE_FROM}"
fi

if [ ! -z "${MESSAGE_SIZE_LIMIT}" ]; then
  postconf -e "message_size_limit = ${MESSAGE_SIZE_LIMIT}"
  echo "Maximum message size set to: ${MESSAGE_SIZE_LIMIT}"
fi

# Set incoming port number in main.cf
sed -i '/ inet /s/^smtp/2500/' /etc/postfix/master.cf

# clean up old runs in case this is a persistent volume mount.
rm -f /var/spool/postfix/pid/master.pid

exec /usr/sbin/postfix -c /etc/postfix start-fg
