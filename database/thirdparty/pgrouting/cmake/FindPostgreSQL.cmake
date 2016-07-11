# - Find PostgreSQL
# Find the PostgreSQL includes and client library
# This module defines
#  POSTGRESQL_INCLUDE_DIR, where to find POSTGRESQL.h
#  POSTGRESQL_LIBRARIES, the libraries needed to use POSTGRESQL.
#  POSTGRESQL_FOUND, If false, do not try to use PostgreSQL.
#
# Copyright (c) 2006, Jaroslaw Staniek, <js@iidea.pl>
#
# Redistribution and use is allowed according to the terms of the BSD license.
# For details see the accompanying COPYING-CMAKE-SCRIPTS file.

# Add the postgresql and mysql include paths here


if(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES AND POSTGRESQL_EXECUTABLE)
   set(POSTGRESQL_FOUND TRUE)
else(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES AND POSTGRESQL_EXECUTABLE)

#  find_path(POSTGRESQL_INCLUDE_DIR libpq-fe.h

 FIND_PROGRAM(POSTGRESQL_EXECUTABLE postgres)
 MESSAGE(STATUS "POSTGRESQL_EXECUTABLE is " ${POSTGRESQL_EXECUTABLE})

 # this is slightly nonsensical now that we only support Postgres 9.1.5+ (extension support)
 FIND_PATH(POSTGRESQL_INCLUDE_DIR postgres.h
      # centos 6.3+
      /usr/pgsql-9.2/include/server
      /usr/pgsql-9.1/include/server
      /usr/include/server
      /usr/include/pgsql/server
      /usr/local/include/pgsql/server
      /usr/include/postgresql/server
      /usr/include/postgresql/*/server
      /usr/local/include/postgresql/server
      /usr/local/include/postgresql/*/server
      $ENV{ProgramFiles}/PostgreSQL/*/include/server
      $ENV{SystemDrive}/PostgreSQL/*/include/server
      )

  FIND_LIBRARY(POSTGRESQL_LIBRARIES NAMES pq libpq
     PATHS
     /usr/pgsql-9.2/lib
     /usr/pgsql-9.1/lib
     /usr/lib
     /usr/local/lib
     /usr/lib/postgresql
     /usr/lib64
     /usr/local/lib64
     /usr/lib64/postgresql
     $ENV{ProgramFiles}/PostgreSQL/*/lib/ms
     $ENV{SystemDrive}/PostgreSQL/*/lib/ms
     )
      
  if(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES)
    set(POSTGRESQL_FOUND TRUE)
    message(STATUS "Found PostgreSQL: ${POSTGRESQL_INCLUDE_DIR}, ${POSTGRESQL_LIBRARIES}")
    INCLUDE_DIRECTORIES(${POSTGRESQL_INCLUDE_DIR})
  else(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES)
    set(POSTGRESQL_FOUND FALSE)
    message(FATAL_ERROR "PostgreSQL not found.")
  endif(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES)

  mark_as_advanced(POSTGRESQL_INCLUDE_DIR POSTGRESQL_LIBRARIES)

endif(POSTGRESQL_INCLUDE_DIR AND POSTGRESQL_LIBRARIES AND POSTGRESQL_EXECUTABLE)
