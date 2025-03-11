#!/bin/bash

ROOT_DIR='/root'

# carto source code location
CARTO_DIR='/root/src/openstreetmap-carto'

# directory to store pbf data
DATA_DIR='/root/data'

# log file to monitor process of db population from pbf file
DB_LOG_FILE='db.log'

# log file to monitor getting external data
RENDERD_LOG_FILE='renderd.log'

OSM_FILE='/root/data/data.osm.pbf'
TAG_TRANSFORM_SCRIPT="$CARTO_DIR/openstreetmap-carto.lua"

wait_pg_to_start() {
  local timeout=60
  local counter=0

  until pg_isready -h localhost -p 5432 -U postgres; do
    sleep 2
    ((counter+=2))
    
    if [ $counter -ge $timeout ]; then
      echo "Timeout reached while waiting for PostgreSQL to start."
      return 1
    fi
  done

  echo "PostgreSQL is up!"
  return 0
}

generate_mapnik_config_xml() {
  carto $CARTO_DIR/project.mml > $CARTO_DIR/mapnik.xml

  return 0
}

configure_pg() {
  echo "Enabling and starting postgresql.service"
  systemctl enable --now postgresql

  wait_pg_to_start

  sudo -u postgres createuser _renderd && \
  sudo -u postgres createdb -E UTF8 -O _renderd gis
  sudo -u postgres psql -d gis -c "CREATE EXTENSION postgis;"
  sudo -u postgres psql -d gis -c "CREATE EXTENSION hstore;"
  sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO _renderd;"
  sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO _renderd;"

  return 0
}

configure_carto() {
  chmod o+rx $ROOT_DIR

  if [ -f "$OSM_FILE" ] && [ ! -f "$DB_LOG_FILE.complete" ]; then
    touch $DB_LOG_FILE
    chown _renderd $DB_LOG_FILE
    sudo -u _renderd osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script $TAG_TRANSFORM_SCRIPT -C 2500 --number-processes 1 -S $CARTO_DIR/openstreetmap-carto.style $OSM_FILE  2>&1 | tee -a $DB_LOG_FILE
    touch /db.log.complete
  fi

  cd $CARTO_DIR
  sudo -u _renderd psql -d gis -f indexes.sql
  sudo -u _renderd psql -d gis -f functions.sql

  generate_mapnik_config_xml

  return 0
}

configure_renderd() {
  cd $CARTO_DIR
  if [ -f "/renderd.log.complete" ]; then
    return 0
  fi

  touch /renderd.log
  chown _renderd /renderd.log
  mkdir data
  sudo chown _renderd data
  sudo -u _renderd scripts/get-external-data.py 2>&1 | tee -a /renderd.log
  scripts/get-fonts.sh 2>&1 | tee -a /renderd.log
  touch /renderd.log.complete

  return 0
}

configure_apache2() {
  a2enconf renderd
  systemctl reload apache2

  return 0
}

main() {
  configure_pg
  configure_carto
  configure_renderd
  configure_apache2

  systemctl daemon-reload
  systemctl restart renderd
  systemctl restart apache2
  /etc/init.d/apache2 restart

  return 0
}

main