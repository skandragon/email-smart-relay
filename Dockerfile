FROM alpine:3
LABEL MAINTAINER Michael Graff <explorer@flame.org>

RUN apk update && apk upgrade && \
    apk add bash gawk cyrus-sasl cyrus-sasl-login cyrus-sasl-crammd5 postfix && \
    rm -rf /var/cache/apk/* && \
    sed -i -e 's/inet_interfaces = localhost/inet_interfaces = all/g' /etc/postfix/main.cf

COPY run.sh /
RUN chmod +x /run.sh
RUN newaliases

EXPOSE 2500
CMD ["/run.sh"]
