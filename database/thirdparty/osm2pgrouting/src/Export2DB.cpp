/***************************************************************************
 *   Copyright (C) 2008 by Daniel Wendt                                    *
 *   gentoo.murray@gmail.com                                               *
 *                                                                         *
 *   This program is free software; you can redistribute it and/or modify  *
 *   it under the terms of the GNU General Public License as published by  *
 *   the Free Software Foundation; either version 2 of the License, or     *
 *   (at your option) any later version.                                   *
 *                                                                         *
 *   This program is distributed in the hope that it will be useful,       *
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of        *
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         *
 *   GNU General Public License for more details.                          *
 *                                                                         *
 *   You should have received a copy of the GNU General Public License     *
 *   along with this program; if not, write to the                         *
 *   Free Software Foundation, Inc.,                                       *
 *   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             *
 ***************************************************************************/

#include "stdafx.h"
#include "Export2DB.h"


#define TO_STR(x)	boost::lexical_cast<std::string>(x)

using namespace std;

Export2DB::Export2DB(string host, string user, string dbname, string port, string passwd, string schema)
:mycon(0)
{
  
  this->conninf="host="+host+" user="+user+" dbname="+ dbname +" port="+port;
  if(!passwd.empty()) {
    this->conninf+=" password="+passwd;
  }

  if (!schema.empty()) {
    this->dbschema = schema;
  }
}


Export2DB::~Export2DB()
{
  PQfinish(mycon);
}

int Export2DB::connect()
{
  int pos = conninf.find (" password=");

  cout << "Connecting to database: " << conninf.substr(0, (pos == -1 ? conninf.length() : pos + 9)) << 
          (pos == - 1 ? "" : "=*****") << " ... ";

  mycon = PQconnectdb(conninf.c_str());
  
  ConnStatusType type = PQstatus(mycon);
  if(type == CONNECTION_BAD)
  {
    cout << "failed" << endl;
    return 1;
  }
  else
  {
    cout << "success" << endl;

    // set schema for session
    setSchema();

    return 0;
  }
/***
      CONNECTION_STARTED: Waiting for connection to be made.
      CONNECTION_MADE: Connection OK; waiting to send.
      CONNECTION_AWAITING_RESPONSE: Waiting for a response from the postmaster.
      CONNECTION_AUTH_OK: Received authentication; waiting for backend start-up.
    CONNECTION_SETENV: Negotiating environment.
***/
}

void Export2DB::setSchema()
{
  if (! dbschema.empty()) {
    cout << "Setting schema to " << dbschema << endl;

    string sql = "SET search_path = '" + dbschema + "', 'public';";
    const PGresult *result = PQexec(mycon, sql.c_str());

    checkResultStatus( result, sql, "setting schema to " + dbschema );
  }
}

void Export2DB::checkResultStatus (const PGresult *result, string query, string action)
{
  if (PQresultStatus (result) == PGRES_FATAL_ERROR) {
    cerr << "Failed " << action << endl;
    cerr << "Query executed: " << query << endl;
    cerr << "Database error: " << PQresultErrorMessage (result) << endl;

    throw "FATAL error, aborting";
  }
}

void Export2DB::createTables()
{
  string sql;

  cout << "Creating PGRouting tables" << endl;

  sql += "CREATE TABLE edges (              \
            gid integer PRIMARY KEY,       \
            osm_id bigint,                 \
            class_id integer,              \
            length double precision,       \
            name char(200),                \
            x1 double precision,           \
            y1 double precision,           \
            x2 double precision,           \
            y2 double precision,           \
            reverse_cost double precision, \
            rule text,                     \
            to_cost double precision,      \
            the_geom GEOMETRY (LINESTRING, 4326) \
          );                               \
          CREATE TABLE types (id integer, name char(200)); \
          CREATE TABLE classes (id integer, type_id integer, name char(200), cost double precision);";

  const PGresult *result = PQexec(mycon, sql.c_str());

  checkResultStatus( result, sql, "creating edge table" );
}

void Export2DB::dropTables()
{
  string sql;

  cout << "Dropping PGRouting tables" << endl;

  sql += "DROP TABLE edges;  \
          DROP TABLE types; \
          DROP TABLE classes;";

  const PGresult *result = PQexec(mycon, sql.c_str());
}

void Export2DB::exportEdge(Way* way)
{
  string query = "INSERT into edges(osm_id, class_id, length, x1, y1, x2, y2, the_geom, reverse_cost, name) ";

  query += "SELECT m.osm_id, c.id, m.length, m.x1, m.y1, m.x2, m.y2, m.the_geom, m.reverse_cost, m.name \
              FROM ( \
                VALUES (";

  // cannot safely use the way id cos a way may have multiple routeable 
  // classes, eg. vehicle and cycling attributes, instead rely on a
  // database serial for gid
  query += boost::lexical_cast<string>(way->osmId) + ","
        +  boost::lexical_cast<string>(way->length) + "," 
        +  boost::lexical_cast<string>(way->m_NodeRefs.front()->lon) + ","
        +  boost::lexical_cast<string>(way->m_NodeRefs.front()->lat) + ","
        +  boost::lexical_cast<string>(way->m_NodeRefs.back()->lon)  + ","
        +  boost::lexical_cast<string>(way->m_NodeRefs.back()->lat) + ","
        + "public.ST_GeometryFromText('" + way->geom + "', 4326)";

  if(way->oneway)
  {
      query += ", " + boost::lexical_cast<string>(way->length*1000000);
  }
  else
  {
      query += ", " + boost::lexical_cast<string>(way->length);
  }  

  if(!way->name.empty()) {
    query += ",$$" + way->name + "$$";
  }
  else {
    query += ",NULL";
  }
    

  query += ") ) AS m (osm_id, length, x1, y1, x2, y2, the_geom, reverse_cost, name) \
            JOIN ( \
              VALUES ";

  // add multiple type/class pairs
  for (int i = 0; i < way->categories.size(); i++) {
    pair <string, string> &category = way->categories.at(i);

    query += (i > 0 ? ",($$" : "($$")
          +  category.first  + 
          +  "$$,$$" 
          + category.second + 
          +  "$$)";
  }

  query += "   ) AS cat (type, class)         \
                 ON 1 = 1                     \
            JOIN types AS t                   \
                 ON cat.type = t.name         \
            JOIN classes AS c                 \
                 ON t.id      = c.type_id AND \
                    cat.class = c.name";
  
  const PGresult *result = PQexec(mycon, query.c_str());

  checkResultStatus ( result, query, "exporting edge" + boost::lexical_cast<string>(way->id) );
}

void Export2DB::exportType(Type* type)
{
  string query = "INSERT into types(id, name) values(";
  
  query+=boost::lexical_cast<string>(type->id) + ", '" + type->name +"');";
  const PGresult *result = PQexec(mycon, query.c_str());

  checkResultStatus ( result, query, "exporting type" + boost::lexical_cast<string>(type->id) );
}

void Export2DB::exportClass(Type* type, Class* clss)
{
  string query = "INSERT into classes(id, type_id, name) values(";
  
  query+=boost::lexical_cast<string>(clss->id) + ", " + boost::lexical_cast<string>(type->id) + ", '" + clss->name +"');";
  const PGresult *result = PQexec(mycon, query.c_str());

  checkResultStatus ( result, query, "exporting class" + boost::lexical_cast<string>(clss->id) );
}

void Export2DB::createTopology( bool clean )
{
  string sql = ("");

  if ( clean ) {
    // clean run, osm2pgrouting has created the tables, add the columns
    // needed for creating topology
    sql.append (
      "ALTER TABLE edges ADD COLUMN source integer;                           \
       ALTER TABLE edges ADD COLUMN target integer;                           \
       CREATE INDEX source_idx ON edges(source);                              \
       CREATE INDEX target_idx ON edges(target);                              \
       CREATE INDEX geom_idx ON edges USING GIST(the_geom GIST_GEOMETRY_OPS);"
       );
  }
  sql.append ("SELECT assign_vertex_id('" + this->dbschema + "','edges', 0.00001, 'the_geom', 'gid');");

  const PGresult *result = PQexec (mycon, sql.c_str());

  checkResultStatus( result, sql, "creating topology" );
}
