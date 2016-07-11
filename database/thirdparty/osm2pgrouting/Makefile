CC = g++

SRC = src/Export2DB.cpp src/math_functions.cpp src/Node.cpp src/OSMDocumentParserCallback.cpp src/Way.cpp src/OSMDocument.cpp src/Type.cpp src/Class.cpp src/Configuration.cpp src/ConfigurationParserCallback.cpp

DEPS = src/XMLParser.cpp

INC = -I./ -Isrc -I$(shell pg_config --includedir)

LIB = -L$(shell pg_config --libdir)

MAIN = src/osm2pgrouting.cpp

all:
	$(CC) -c $(SRC) $(INC) -ggdb3
	$(CC) -c $(DEPS) $(INC) -ggdb3
	$(CC) -o osm2pgrouting $(MAIN) *.o $(INC) $(LIB) -lexpat -ggdb3 -lpq
	rm *.o
clean:
	rm osm2pgrouting

