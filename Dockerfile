FROM alpine:latest

LABEL MAINTAINER="Sebastian Zoll"

RUN apk add --no-cache \
    curl jq graphviz git bash \
    && cd / \
    && git clone https://github.com/sips4711/ocp4upc.git \
    && mv ocp4upc/ocp4upc.sh /bin/ \
    && chmod 777 /bin/ocp4upc.sh

WORKDIR /documents
VOLUME /documents

CMD ["/bin/ocp4upc.sh"]
