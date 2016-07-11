# TOTUS deployment
The test data is for Auckland, New Zealand.

## Requirements:

### System:

1. GNU bash
2. PostgreSQL 9.1.x or newer (full development and server install)
3. PostGIS 2.x or newer (full development and server install)
4. gcc, gcc-c++
5. cmake
6. boost-devel, expat-devel, gdal
7. perl, perl-Log-Log4perl, perl-Spreadsheet-ParseExcel
8. wget
9. ant
10. pgRouting
	1. cd database/thirdparty/pgrouting 
	2. to install run cmake . 
	3. make
	4. sudo make install
11. FeatureServer requires the following python modules (use package manager or pip-python to install)
	1. dxfwrite
	2. lxml
	3. Cheetah
	4. simplejson
	5. psycopg2
	6. shortuuid
	7. mod_python

### Datasets and configuration:

1. Traffic model output, see database/data/test/traffic/2006 for test data set
2. Statistics New Zealand census data sets (www.stats.govt.nz), see database/data/test/census for test data set
3. INI file to configure TOTUS

## Steps:

1. Copy and modify the INI file config/sample.ini 
2. Prepare TOTUS build scripts, run ./prepare.sh -c <INI file>
3. Build and deploy TOTUS, run ./build.sh -c <INI file>

## NOTES:

If needed, Prepare the PostgreSQL template1 (default for all new databases) by enabling the postGIS and pgRouting extensions:

psql -h localhost -U postgres -d template1 <<EOF
    CREATE EXTENSION postgis;
    CREATE EXTENSION pgrouting;
EOF

