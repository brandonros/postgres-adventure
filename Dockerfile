FROM bitnami/postgresql:17.6.0-debian-12-r4

USER root

# Install build dependencies
RUN install_packages \
    libcurl4-openssl-dev \
    libssl-dev \
    liblz4-dev \
    libxslt1-dev \
    libxml2-dev \
    zlib1g-dev \
    libedit-dev \
    curl \
    unzip \
    make \
    gcc \
    build-essential

# Build and install pglogical extension
RUN cd /tmp && \
    curl -L -o pglogical.zip https://github.com/2ndQuadrant/pglogical/archive/refs/tags/REL2_4_6.zip && \
    unzip pglogical.zip && \
    cd pglogical-* && \
    export PG_CONFIG=/opt/bitnami/postgresql/bin/pg_config && \
    make && \
    make install && \
    rm -rf /tmp/pglogical*

# Clean up build dependencies
RUN apt-get remove -y \
        make \
        gcc \
        curl \
        unzip \
        build-essential && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Fix permissions for the extensions
RUN chmod g+rwX /opt/bitnami/postgresql/lib/pglogical.so /opt/bitnami/postgresql/share/extension/pglogical*

USER 1001
