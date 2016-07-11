1. Osmosis

Downloaded from OSM.

Version: Osmosis 0.43
URL: http://bretth.dev.openstreetmap.org/osmosis-build/osmosis-latest.zip

2. OSM2PGrouting

We maintain an outdated version of this tool, last synched with revision 358

Path: trunk
URL: http://pgrouting.postlbs.org/svn/pgrouting/tools/osm2pgrouting/trunk
Repository Root: http://pgrouting.postlbs.org/svn/pgrouting
Repository UUID: d21bcd6f-0036-404f-87c1-d983b28855fd
Revision: 358
Node Kind: directory
Last Changed Author: daniel
Last Changed Rev: 357
Last Changed Date: 2010-07-01 18:17:54 +1200 (Thu, 01 Jul 2010)

NOTE:
a. repo above have been moved to https://github.com/pgRouting/osm2pgrouting
b. project have added support for relations, eg. to build turn restrictions
c. as of Feb 2013 OSM IDs exceeded 32 bit, modified local version to support it

3. PGRouting

We maintain a modified version 1.06 of this tool.

Version: PGRouting 1.06
URL: https://github.com/pgRouting/pgrouting

git clone git://github.com/pgRouting/pgrouting.git pgrouting

commit 18bfb76a298358d086162204631c9bc2a5f2d3cd
Author: Daniel Kastl <daniel@georepublic.de>
Date:   Wed Nov 14 11:53:34 2012 +0900

NOTE:
The 2.0 release is not backwards compatible with the 1.x releases because they
have totally restructured the API and the source code to position the product
for additional future growth.
