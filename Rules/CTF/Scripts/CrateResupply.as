
#include "MakeCrate.as"
#include "MakeSeed.as"

//TODO: config file for the variables?
//shipment frequency in seconds
const int shipmentFrequency = 60;
//the number of creates sent at the start of the game (because we probably need more mats to start building)
const int initialCrateMultiplier = 10;
//offset the shipment from gametime of 0, i.e. the time the that the first shipment is sent (after the initial shipment, which is always onInit)
const int shipmentStartTime = 0;
//offset the shipment x position from the base +ve is behind, -ve is in front
const float shipmentBaseOffset = 0.0f;

//shipment success rate (e.g. could make it every 30 seconds, but only a 25% chance of success)
const int shipmentProbability = 100;

//TODO: drop speed and other crate create args?

//same properties for the bonus shipment
const int bonusShipmentFrequency = 140;
//minimum working value is 1, any value less than one will not send the first shipment
const int bonusShipmentStartTime = 0;
const int bonusShipmentProbability = 75;		//%
const int bonusShipmentItemMin = 2;
const int bonusShipmentItemMax = 4;
//probability of adding each item between the min and max
const int bonusShipmentItemProbability = 70;		//%

class MaterialQuantity {
	string blobName;
	int quantity;

	MaterialQuantity(string blobName, int quantity)
	{
		this.blobName = blobName;
		this.quantity = quantity;
	}
}

MaterialQuantity[] shipmentMaterialCounts = {
	MaterialQuantity("mat_wood", 250),
	MaterialQuantity("mat_stone", 120),
	MaterialQuantity("mat_arrows", 20)
};

//all the items that can be put into a bonus shipment
//duplicated entries are added to increase the probability of that option
MaterialQuantity[] bonusShipments = {
	MaterialQuantity("keg", 1),
	MaterialQuantity("keg", 1),
	MaterialQuantity("mat_bombs", 2),
	MaterialQuantity("mat_bombs", 2),
	//MaterialQuantity("mat_bombs", 2),
	MaterialQuantity("mat_bombs", 1),
	MaterialQuantity("mat_waterbombs", 1),
	//MaterialQuantity("mat_arrows", 30),
	MaterialQuantity("mat_arrows", 30),
	MaterialQuantity("mat_bombarrows", 2),
	MaterialQuantity("mat_bombarrows", 2),
	MaterialQuantity("mat_bombarrows", 1),
	MaterialQuantity("mat_waterarrows", 1),
	MaterialQuantity("mat_firearrows", 2),
	MaterialQuantity("mat_firearrows", 2),
	//MaterialQuantity("mat_bolts", 12),
	MaterialQuantity("mat_stone", 300),
	MaterialQuantity("mat_stone", 300),
	//MaterialQuantity("mat_stone", 200),
	MaterialQuantity("drill", 1),
	MaterialQuantity("chicken", 1),
	MaterialQuantity("sponge", 1),
	MaterialQuantity("food", 2),
	//MaterialQuantity("food", 1),
	MaterialQuantity("mine", 2)
	//tried these, but they need special handling to add to the crate, can do it later
	//best place to look for examples is the map loader
	//a generic function for all blobs would be useful, takes a name(or enum maybe?) and does whatever it needs to do to create it, depending on the blob
	//MaterialQuantity("trampoline", 1),
	//MaterialQuantity("catapult", 1),
	//MaterialQuantity("bison", 1),
	//MaterialQuantity("shark", 1),
	//MaterialQuantity("filled_bucket", 1),
	//MaterialQuantity("tree_pine", 1),
	//MaterialQuantity("tree_bushy", 1)
};

string base_name() { return "tent"; }


void onInit(CRules@ this)
{
	//add the command needed for the client to hear shipment sounds
	this.addCommandID("shipment sound");
	onRestart(this);
}

void onRestart(CRules@ this)
{
	//spawn the initial crates on the server
	if(isServer())
	{
		for (int i = 0; i < initialCrateMultiplier; i++)
		{
			sendShipment(this, (i - (initialCrateMultiplier/2)) * 20.0f, true);
		}
	}
}

void onTick(CRules@ this)
{
	if (isServer())
	{
		if (shouldSendShipment())
		{
			sendShipment(this, shipmentBaseOffset);
		}
		if (shouldSendBonusShipment())
		{
			sendBonusShipment(this);
		}
	}
}

void onCommand(CRules@ this, u8 cmd, CBitStream @params)
{
	if (cmd == this.getCommandID("shipment sound") && !isServer())
	{
		Sound::Play("/ShipmentHorn.ogg");
	}
}

bool shouldSendShipment()
{
	//just want to send a shipment periodically with a chance to fail, can make more complex logic later if desired
	if (getGameTime() % getTicksASecond() == 0)
	{
		s32 gameTimeSeconds = getGameTime()/getTicksASecond();
		if (gameTimeSeconds < shipmentStartTime) return false;
		return ((gameTimeSeconds-shipmentStartTime) % shipmentFrequency == 0) && (XORRandom(100) < shipmentProbability);
	}
	return false;
}

bool shouldSendBonusShipment()
{
	//just want to send a shipment periodically with a chance to fail, can make more complex logic later if desired
	if (getGameTime() % getTicksASecond() == 0)
	{
		s32 gameTimeSeconds = getGameTime()/getTicksASecond();
		if (gameTimeSeconds < bonusShipmentStartTime) return false;
		return ((gameTimeSeconds-bonusShipmentStartTime) % bonusShipmentFrequency == 0) && (XORRandom(100) < bonusShipmentProbability);
	}
	return false;
}

void fillShipment(CRules@ this, CBlob@ crate)
{
	for(int j=0;j<shipmentMaterialCounts.length;j++)
	{
		CBlob@ mat = server_CreateBlob(shipmentMaterialCounts[j].blobName);
		mat.server_SetQuantity(shipmentMaterialCounts[j].quantity);
		if (mat !is null)
		{
			crate.server_PutInInventory(mat);
		}
	}
}

/*
 * spawnLow: spawn the crate near the ground, useful for the start of the game so players don't need to wait for them
 */
void sendShipment(CRules@ this, float offset = 0.0f, bool spawnLow = false)
{
	CBlob@[] bases;
	getBlobsByName(base_name(), @bases);

	for (uint i = 0; i < bases.length; ++i)
	{
		CBlob@ base = bases[i];

		// spawn crate
		Vec2f droppos = base.getPosition();
		//depending on what team the base is, "forward" is in a different direction (so offset needs to be inverted)
		droppos.x += (base.getTeamNum() == 0) ? -1.0f * offset : offset;
		if(!spawnLow)
		{
			//randomises the spawn position and sets the y high in the sky
			droppos = getDropPosition(droppos);
		}
		else
		{
			//10 tiles above the ground
			CMap@ map = getMap();
			droppos.y = map.getLandYAtX(droppos.x) + map.tilesize * 10.0f;
		}
		CBlob@ crate = server_MakeCrateOnParachute("", "", 5, base.getTeamNum(), droppos);
		if (crate !is null)
		{
			// make unpack button
			crate.Tag("unpackall");
			fillShipment(this, crate);
		}
	}
}

void fillBonusShipment(CRules@ this, CBlob@ crate)
{
	for (int i = 0; i < bonusShipmentItemMax; i++)
	{
		//guarantee item below the min threshold, then random chance between min and max
		if (i < bonusShipmentItemMin || XORRandom(100) < bonusShipmentItemProbability)
		{
			//pick a random item from the list
			int itemIndex = XORRandom(bonusShipments.length);
			string blobName = bonusShipments[itemIndex].blobName;
			CBlob@ mat = null;
			//would be good if this function could accept a wider range of entities, want a helper function for that to handle special cases
			@mat = server_CreateBlob(blobName);
			mat.server_SetQuantity(bonusShipments[itemIndex].quantity);
			if (mat !is null)
			{
				crate.server_PutInInventory(mat);
			}
		}
	}
}

void sendBonusShipment(CRules@ this)
{
	//get the middle of the map
	CMap@ map = getMap();
	Vec2f droppos = Vec2f((map.tilemapwidth*map.tilesize)/2, 0.0f);
	CBlob@ crate = server_MakeCrateOnParachute("", "", 5, -1, getDropPosition(droppos));
	crate.Tag("unpackall");

	fillBonusShipment(this, crate);

	CBitStream params;
	this.SendCommand(this.getCommandID("shipment sound"), params);
}
