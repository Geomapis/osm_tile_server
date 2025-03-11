FROM geomapis/ubuntu-24.04-systemd:latest

RUN apt update && apt upgrade -y

RUN apt install -y \
    screen \
    locate \
    libapache2-mod-tile \
    renderd \
    git-core \
    tar \
    unzip \
    wget \
    bzip2 \
    apache2 \
    lua5.1 \
    mapnik-utils \
    python3-mapnik \
    python3-psycopg2 \
    python3-yaml \
    gdal-bin \
    npm \
    node-carto \
    postgresql \
    postgresql-contrib \
    postgis \
    postgresql-16-postgis-3 \
    postgresql-16-postgis-3-scripts \
    osm2pgsql \
    net-tools \
    curl \
    rsyslog
RUN npm install -g carto

COPY scripts /scripts
RUN chmod +x /scripts/*.sh

COPY configs/configure.service /etc/systemd/system/configure.service
COPY configs/renderd.conf /etc/renderd.conf
COPY configs/renderd.conf.apache2 /etc/apache2/conf-available/renderd.conf
COPY configs/sample_leaflet.html /var/www/html/sample_leaflet.html

RUN systemctl enable configure.service
RUN systemctl enable renderd.service
RUN systemctl enable apache2.service
RUN systemctl enable rsyslog.service

COPY data /root/data
RUN chown _renderd /root/data
