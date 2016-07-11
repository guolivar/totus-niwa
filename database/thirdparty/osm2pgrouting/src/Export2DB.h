/***************************************************************************
 *   Copyright (C) 2008 by Daniel Wendt                      *
 *   gentoo.murray@gmail.com                            *
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

#ifndef EXPORT2DB_H
#define EXPORT2DB_H

//#include "postgresql/libpq-fe.h"
#include "libpq-fe.h"
#include "Node.h"
#include "Way.h"
#include "Type.h"
#include "Class.h"

using namespace osm;

/**
 * This class connects to a postgresql database. For using this class,
 * you also need to install postgis and pgrouting 
 */

class Export2DB
{

public:
  /**
   * Constructor
   * @param host Host address of the database
   * @param user a user, who has write access to the database
   * @param dbname name of the database
   * @params port database server port number
   * @params password user password
   * @params schema database schema, if needed
   */ 
   Export2DB(std::string host, std::string user, std::string dbname, std::string port,
             std::string password, std::string schema);
   /**
    * Destructor
    * closes the connection to the database
    */  
   ~Export2DB();
   
   //! connects to database
   int connect();
   //! creates needed tables
   void createTables();
   //! exports ways as edges to the database
   void exportEdge(Way* way);

   void exportType(Type* type);
   void exportClass(Type* type, Class* clss);
   void setSchema();

   /** 
    * creates the topology
    * Be careful, it takes some time.
    * 
    * for example:
    * complete germany: OSM file with a size of 1,1 GiB.
    * Export and create topology:
    * time took circa 30 hours on an Intel Xeon 2,4 GHz with 2 GiB Ram.
    * But only for the streettypes "motorway", "primary" and "secondary"
    */ 
   void createTopology( bool clean = false);
   //! Be careful! It deletes the created tables!
   void dropTables();

   //! Check the result of the export query executed
   void checkResultStatus (const PGresult *result, std::string query, std::string action);

private:
  PGconn *mycon;
  std::string conninf;
  std::string dbschema;
};

#endif
