#!/bin/bash
CARTO_DIR='/root/src/openstreetmap-carto'
ROOT_DIR='/root'
DATA_DIR='/root/data'

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
}

configure_carto() {
  chmod o+rx $ROOT_DIR

  if ls $DATA_DIR/*.pbf &>/dev/null; then
    touch /db_log
    chown _renderd /db_log
    sudo -u _renderd osm2pgsql -d gis --create --slim  -G --hstore --tag-transform-script $ROOT_DIR/src/openstreetmap-carto/openstreetmap-carto.lua -C 2500 --number-processes 1 -S $ROOT_DIR/src/openstreetmap-carto/openstreetmap-carto.style $ROOT_DIR/data/armenia-latest.osm.pbf  2>&1 | tee -a /db_log
  fi

  cd $ROOT_DIR/src/openstreetmap-carto/
  sudo -u _renderd psql -d gis -f indexes.sql
  sudo -u _renderd psql -d gis -f functions.sql
}

configure_renderd() {
  cd $ROOT_DIR/src/openstreetmap-carto/
  touch /logfile
  chown _renderd /logfile
  mkdir data
  sudo chown _renderd data
  sudo -u _renderd scripts/get-external-data.py 2>&1 | tee -a /logfile
}

configure_apache2() {
  a2enconf renderd
  systemctl reload apache2
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
}

main