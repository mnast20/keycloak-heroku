FROM quay.io/keycloak/keycloak:latest

COPY docker-entrypoint.sh /opt/keycloak/tools

ENTRYPOINT [ "/opt/keycloak/tools/docker-entrypoint.sh" ]
CMD ["-b", "0.0.0.0"]

