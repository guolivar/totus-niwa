/***************************************************************************
 *   Copyright (C) 2008 by Daniel Wendt   								   *
 *   gentoo.murray@gmail.com   											   *
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

#ifndef OSMDOCUMENTPARSERCALLBACK_H
#define OSMDOCUMENTPARSERCALLBACK_H

#include <string.h>
#include "XMLParser.h"

namespace osm
{

class OSMDocument;
class Way;

/**
	Parser callback for OSMDocument files
*/
class OSMDocumentParserCallback : public xml::XMLParserCallback
{	
	//! reference to a OSMDocument object
	OSMDocument& m_rDocument;
	//! current way, which will be parsed
	Way* m_pActWay;

	virtual void StartElement( const char *name, const char** atts );

	virtual void EndElement( const char* name );

	virtual void SetContent( const char* ch, int len)
	{
	}

	virtual void ProcessingInstruction( const char* target, const char* data )
	{
	}

	virtual void CDataBlockInternal(const char *value, int len)
	{
	}


public:
	/**
	 *	Constructor
	 */
	OSMDocumentParserCallback( OSMDocument& doc )
	:
		m_rDocument( doc ),
		m_pActWay( 0 )
	{
	}

}; // class OSMDocumentParserCallback

}; // end namespace osm

#endif
