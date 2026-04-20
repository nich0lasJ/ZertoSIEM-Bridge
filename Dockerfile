FROM fluent/fluentd:v1.17-debian-1

USER root

# System deps for native gem extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    openssl \
    curl \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install FluentD output plugins
RUN fluent-gem install \
    fluent-plugin-rewrite-tag-filter \
    fluent-plugin-elasticsearch \
    fluent-plugin-splunk-hec \
    fluent-plugin-azure-loganalytics \
    fluent-plugin-record-modifier \
    fluent-plugin-prometheus \
    && fluent-gem cleanup

# App directories
RUN install -d -m 0755 /etc/fluent/outputs \
    && install -d -m 0750 /etc/fluent/certs \
    && install -d -m 0755 /var/log/fluentd

COPY config/fluent.conf        /etc/fluent/fluent.conf
COPY config/zerto_parse.conf   /etc/fluent/zerto_parse.conf
COPY config/outputs/           /etc/fluent/outputs/
COPY scripts/entrypoint.sh     /entrypoint.sh

RUN chmod +x /entrypoint.sh

# Syslog ports
EXPOSE 514/udp 514/tcp 6514/tcp
# Prometheus metrics
EXPOSE 24231/tcp

ENTRYPOINT ["/entrypoint.sh"]
