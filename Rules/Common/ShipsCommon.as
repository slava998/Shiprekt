shared class Ship
{
	u32 id;                   //ship's specific identification 
	ShipBlock[] blocks;       //all blocks on a ship
	Vec2f pos, vel;           //position, velocity
	f32 angle, angle_vel;     //angle of ship, angular velocity
	Vec2f old_pos, old_vel;   //comparing new to old position, velocity
	f32 old_angle;            //comparing new to old angle
	f32 mass, carryMass;      //weight of the entire ship, weight carried by a player
	CBlob@ centerBlock;       //the block in the center of the entire ship
	bool initialized;	      //onInit for ships
	bool colliding;           //used in ship collisions to stop ships from colliding twice in the same tick
	uint soundsPlayed;        //used in limiting sounds in propellers
	string owner;             //username of the player who owns the ship
	bool isMothership;        //is the ship connected to a core?
	bool isStation;           //is the ship connected to a station?
	bool isSecondaryCore;     //is the ship connected to an auxillary core?
	
	Vec2f net_pos, net_vel;        //network
	f32 net_angle, net_angle_vel;  //network

	Ship()
	{
		angle = angle_vel = old_angle = mass = carryMass = 0.0f;
		initialized = false;
		colliding = false;
		isMothership = false;
		isStation = false;
		isSecondaryCore = false;
		@centerBlock = null;
		soundsPlayed = 0;
		owner = "";
	}
};

shared class ShipBlock
{
	u16 blobID;
	Vec2f offset;
	f32 angle_offset;
};

// Grab a ship object from the index
Ship@ getShip(const int colorIndex)
{
	if (colorIndex > 0)
	{
		Ship[]@ ships;
		if (getRules().get("ships", @ships) && colorIndex <= ships.length)
			return ships[colorIndex-1];
	}
	return null;
}

// Reference a ship from a non-block (e.g human)
Ship@ getShip(CBlob@ this)
{
	CBlob@[] blobsInRadius;
	if (getMap().getBlobsInRadius(this.getPosition(), 1.0f, @blobsInRadius)) 
	{
		const u8 blobsLength = blobsInRadius.length;
		for (u8 i = 0; i < blobsLength; i++)
		{
            const int color = blobsInRadius[i].getShape().getVars().customData;
            if (color > 0)
            	return getShip(color);
		}
	}
    return null;
}

// Gets the block blob wherever 'this' is positioned
CBlob@ getShipBlob(CBlob@ this)
{
	CBlob@ b = null;
	CBlob@[] blobsInRadius;
	if (getMap().getBlobsInRadius(this.getPosition(), 1.0f, @blobsInRadius))
	{
		f32 mDist = 9999;
		const u8 blobsLength = blobsInRadius.length;
		for (u8 i = 0; i < blobsLength; i++)
		{
			CBlob@ blob = blobsInRadius[i];
			if (blob.getShape().getVars().customData > 0)
			{
				f32 dist = this.getDistanceTo(blob);
				if (dist < mDist)
				{
					@b = blob;
					mDist = dist;
				}
			}
		}
	}

	return b;
}

// Gets the mothership core block on determined team 
CBlob@ getMothership(const u8 team)
{
	if (team < 8)
	{
		CBlob@[]@ cores;
		if (getRules().get("motherships", @cores))
			return cores[team];
	}
	return null;
}

// Gets the name of the mothership's captain
string getCaptainName(u8 team)
{
	CBlob@ core = getMothership(team);
	if (core !is null)
	{
		Ship@ ship = getShip(core.getShape().getVars().customData);
		if (ship !is null)
			return ship.owner;
	}
	return "";
}

// Paths to specified block from start, returns true if it is connected
// Doesn't path through couplings and repulsors
bool coreLinkedPathed(CBlob@ this, CBlob@ core, u16[] checked, u16[] unchecked, bool colorCheck = true)
{
	u16 networkID = this.getNetworkID();
	checked.push_back(networkID);
	
	// remove from unchecked blocks if this was marked as unchecked
	s16 uncheckedIndex = unchecked.find(networkID);
	if (uncheckedIndex > -1)
	{
		unchecked.erase(uncheckedIndex);
	}
	
	CBlob@[] overlapping;
	if (this.getOverlapping(@overlapping))
	{
		Vec2f thisPos = this.getPosition();
		Vec2f corePos = core.getPosition();
		const int coreColor = core.getShape().getVars().customData;
		
		f32 minDist = 99999.0f;
		CBlob@ optimal = null;
		const u8 overlappingLength = overlapping.length;
		for (u8 i = 0; i < overlappingLength; i++)
		{
			CBlob@ b = overlapping[i];
			Vec2f bPos = b.getPosition();
			if (checked.find(b.getNetworkID()) >= 0 ||  // no repeated blocks
				(bPos - thisPos).LengthSquared() >= 78 ||       // block has to be adjacent
				b.hasTag("removable") || !b.hasTag("block") ||          // block is not a coupling or repulsor
				(b.getShape().getVars().customData != coreColor && colorCheck))  // is a block, is same ship as core
				continue;
			
			f32 coreDist = (bPos - corePos).Length();
			if (coreDist < minDist)
			{
				minDist = coreDist;
				if (optimal !is null) // put non-optimal blocks as unchecked blocks for future alternative pathing
					unchecked.push_back(optimal.getNetworkID());
				@optimal = b; // set closest blob to core as the optimal route
			}
		}
		if (optimal !is null)
		{
			if (optimal is core)
			{
				// we found the block we were looking for, stop the process
				return true;
			}
			//print(optimal.getNetworkID()+"");
			// continue best estimated path
			return coreLinkedPathed(optimal, core, checked, unchecked, colorCheck);
		}
		else // dead end on path, find next best route from cached 'unchecked' blocks
		{
			if (unchecked.length <= 0)
				return false;
			
			CBlob@ nextBest = getBlobByNetworkID(unchecked[0]);
			if (nextBest !is null)
			{
				// start new path
				unchecked.erase(0);
				//print(nextBest.getNetworkID()+" NEW PATH");
				return coreLinkedPathed(nextBest, core, checked, unchecked, colorCheck);
			}
		}
	}
	return false;
}
