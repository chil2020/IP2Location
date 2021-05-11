#!/bin/bash

# Configuration
TOKEN="DOWNLOAD_TOKEN"
CODE="DB11LITE"

DBHOST="YOUR_DATABASE_HOST"
DBUSER="YOUR_DATABASE_USERNAME"
DBPASS="YOUR_DATABASE_PASSWORD"
DBNAME="YOUR_DATABASE_NAME"

# ----- DO NOT EDIT ANYTHING BELOW THIS LINE ----- #

error() { echo -e "\e[91m[ERROR: $1]\e[m"; }
success() { echo -e "\e[92m$1\e[m"; }

echo "+--------------------------------------------------+"
echo "|   IP2LOCATION AUTOMATED DATABASE UPDATE SCRIPT   |"
echo "|   ============================================   |"
echo "|        Website: http://www.ip2location.com       |"
echo "|        Contact: support@ip2location.com          |"
echo "+--------------------------------------------------+"
echo ""

echo -n "Check for required commands......................... "

for a in wget unzip psql wc find grep; do
	if [ -z "$(which $a)" ]; then
		error "Command \"$a\" not found."
		exit 0
	fi
done

success "[OK]"

if [ ! -d /tmp/ip2location ]; then
	echo -n "Create temporary directory.......................... "
	mkdir /tmp/ip2location

	if [ ! -d /tmp/ip2location ]; then
		error "Failed to create /tmp/ip2location"
		exit 0
	fi
	success "[OK]"
fi

cd /tmp/ip2location

echo -n "Download latest database from IP2Location website... "

wget -O database.zip -q http://www.ip2location.com/download?token=$TOKEN\&file=$CODE 2>&1

if [ ! -f database.zip ]; then
	error "Download failed."
	exit 0
fi

if [ ! -z "$(grep 'NO PERMISSION' database.zip)" ]; then
	 error "Permission denied."
        exit 0
fi

if [ ! -z "$(grep '5 times' database.zip)" ]; then
         error "Download quota exceed."
        exit 0
fi

if [ $(wc -c < database.zip) -lt 102400 ]; then
	error "Download failed."
	exit 0	
fi

success "[OK]"

echo -n "Decompress database package......................... "

unzip -q -o database.zip

if [ -z $(find `pwd` -name 'IP2LOCATION*.CSV') ]; then
	echo "ERROR:"
	exit 0
fi

NAME="$(find `pwd` -name 'IP2LOCATION*.CSV')"

success "[OK]"

echo -n "Create temporary table in database.................. "

RESULT="$(psql -d $DBNAME -U $DBUSER -c 'DROP TABLE IF EXISTS ip2location_database_tmp;' 2>&1 | sed -e 's/NOTICE.*//g')"

if [ ! -z "$(echo $RESULT | grep 'connect')" ]; then
        error "Failed to connect Postgresql host."
        exit 0
fi

if [ ! -z "$(echo $RESULT | grep 'Access denied')" ]; then
	error "Postgresql authentication failed."
	exit 0
fi

RESULT="$(psql -d $DBNAME -U $DBUSER -c 'CREATE TABLE ip2location_database_tmp (ip_from bigint NOT NULL,ip_to bigint NOT NULL,country_code character(2) NOT NULL,country_name character varying(64) NOT NULL,region_name character varying(128) NOT NULL,city_name character varying(128) NOT NULL,latitude real NOT NULL,longitude real NOT NULL,zip_code character varying(30) NOT NULL,time_zone character varying(8) NOT NULL, CONSTRAINT ip2location_database_tmp_pkey PRIMARY KEY (ip_to));' 2>&1 | sed -e 's/NOTICE.*//g')"

if [ ! -z "$(echo $RESULT | grep 'ERROR')" ]; then
	error "Unable to create temporary table. message: "$RESULT
	exit 0
fi
success "[OK]"

echo -n "Start to load CSV into database..................... "

RESULT="$(psql -d $DBNAME -U $DBUSER -c 'COPY ip2location_database_tmp(ip_from, ip_to, country_code, country_name, region_name, city_name, latitude ,longitude, zip_code, time_zone ) FROM '\'${NAME}\''
  DELIMITER '\'','\'' CSV HEADER;' 2>&1 | sed -e 's/NOTICE.*//g')"

if [ ! -z "$(echo $RESULT | grep 'ERROR')" ]; then
        error "Failed: "$RESULT
        exit 0
fi

success "[OK]"

echo -n "Drop existing table................................. "

RESULT="$(psql -d $DBNAME -U $DBUSER -c 'DROP TABLE IF EXISTS ip2location_database;' 2>&1 | sed -e 's/NOTICE.*//g')"

if [ ! -z "$(echo $RESULT | grep 'ERROR')" ]; then
        error "Failed to drop \"ip2location_database\" table."
        exit 0
fi

success "[OK]"

echo -n "Rename table........................................ "

RESULT="$(psql -d $DBNAME -U $DBUSER -c 'ALTER TABLE ip2location_database_tmp RENAME TO ip2location_database;' 2>&1 | sed -e 's/NOTICE.*//g')"

if [ ! -z "$(echo $RESULT | grep 'ERROR')" ]; then
        error "Failed to rename table."
        exit 0
fi

success "[OK]"

echo -n "Perform final clean up.............................. "

rm -rf /tmp/ip2location

success "[OK]"

success "DONE: IP2Location database has been updated."
