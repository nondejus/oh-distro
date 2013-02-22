/*
 * server_test.cpp
 *
 *  Created on: Jan 16, 2013
 *      Author: mfleder
 */

#include <stdio.h>
#include <lcm/lcm-cpp.hpp>
#include <boost/shared_ptr.hpp>
#include "affordance/AffordanceServer.h"
#include "affordance/AffordanceUpWrapper.h"
#include "affordance/AffordanceState.h"
#include <iostream>

using namespace boost;
using namespace std;
using namespace affordance;

/**populates the server w/ a bunch of affordances*/
void runPopulate(const shared_ptr<lcm::LCM> lcm)
{
	AffordanceUpWrapper wrapper(lcm);

	const int mapId = 0;
	int uniqueObjId = 0;

	//sphere
	AffordanceState sphere("Sphere", uniqueObjId++, mapId,
			       KDL::Frame(KDL::Vector(-0.5, -0.5, 0.0)),
			       Eigen::Vector3f( 1.0, 0.0, 1.0 )); //color
	sphere._otdf_type = AffordanceState::SPHERE;
	sphere._params[AffordanceState::RADIUS_NAME] = 0.125;
	wrapper.addNewlyFittedAffordance(sphere);

	//box
	AffordanceState box("Ground Plane", uniqueObjId++, mapId,
			    KDL::Frame(KDL::Vector( 0.0, 0.0, -1.6)),
			    Eigen::Vector3f( 0.75, 0.75, 0.0 ));
	box._otdf_type = AffordanceState::BOX;
	box._params[AffordanceState::LENGTH_NAME] = 100;
	box._params[AffordanceState::WIDTH_NAME]  = 100;
	box._params[AffordanceState::HEIGHT_NAME] = 1.0;
	wrapper.addNewlyFittedAffordance(box);

	//cylinder
	AffordanceState cylinder("Cylinder", uniqueObjId++, mapId,
				 KDL::Frame( KDL::Vector( 0.0, 1.0, 0.0 )),
				 Eigen::Vector3f(0.0, 1.0, 1.0)); //color
	cylinder._otdf_type = AffordanceState::CYLINDER;
	cylinder._params[AffordanceState::RADIUS_NAME] = 0.25;
	cylinder._params[AffordanceState::LENGTH_NAME] = 0.25;
	wrapper.addNewlyFittedAffordance(cylinder);

	//=============
	//add a bunch of affordances w/ just names + ids
//	wrapper.addNewlyFittedAffordance(AffordanceState("steering_cyl",      uniqueObjId++, mapId));
	wrapper.addNewlyFittedAffordance(AffordanceState("box",       uniqueObjId++, mapId));
//	wrapper.addNewlyFittedAffordance(AffordanceState("ladder",      uniqueObjId++, mapId));
//	wrapper.addNewlyFittedAffordance(AffordanceState("cylinder",       uniqueObjId++, mapId));
//	wrapper.addNewlyFittedAffordance(AffordanceState("sphere",  uniqueObjId++, mapId));
//	wrapper.addNewlyFittedAffordance(AffordanceState("box", 		uniqueObjId++, mapId));
//	wrapper.addNewlyFittedAffordance(AffordanceState("ladder_cyl", 	uniqueObjId++, mapId));

	int j = 0;
	boost::posix_time::seconds sleepTime(1); //update every 1 seconds
	while(true)
	{
		//cout << "\n\n===" << j << endl;
		cout << wrapper << endl;
		boost::this_thread::sleep(sleepTime); //======sleep

		//======modify server
		if (j++ == 10)
		{
			//make a modification
		}
	}
}

int main(int argc, char ** argv)
{
	shared_ptr<lcm::LCM> theLcm(new lcm::LCM());
	 if (!theLcm->good())
	 {
	    cerr << "Cannot create lcm object" << endl;
	    return -1;
	 }

    //create the server
    AffordanceServer s(theLcm);

    //thread will add to the affordance server
    //and possibly make changes over time
	boost::thread populateThread = boost::thread(runPopulate, theLcm);

    //lcm loop
    cout << "\nstarting lcm loop" << endl;
    while (0 == theLcm->handle());

    return 0;
}
