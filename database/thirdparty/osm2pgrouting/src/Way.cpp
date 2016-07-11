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

#include "stdafx.h"
#include "Way.h"


namespace osm
{

Way::Way( long long id, bool visible )
:
	id(id),
  osmId(-1),
	visible(visible),
	length(0),
	oneway(false)
{
}

Way::Way( long long id, long long osmId, bool visible )
:
	id(id),
  osmId(osmId),
	visible(visible),
	length(0),
	oneway(false)
{
}

Way::~Way()
{
}

void Way::AddNodeRef( Node* pNode )
{
	if( pNode ) m_NodeRefs.push_back(pNode);
}


} // end namespace osm

