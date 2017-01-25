import numpy
import colorsys
from director import transformUtils

# joints to plot
joints = ["rightHipYaw", "rightHipRoll", "rightHipPitch", "rightKneePitch", "rightAnklePitch", "rightAnkleRoll"]

left_arm_joints = ['l_arm_shz','l_arm_shx','l_arm_ely','l_arm_elx','l_arm_uwy',
  'l_arm_mwx', 'l_arm_lwy']


joints = left_arm_joints

joints = ['l_arm_shx']
# string arrays for EST_ROBOT_STATE and ATLAS_COMMAND
jn = msg.joint_name
jns = msg.joint_names

N = len(joints)
HSV_tuples =      [(0., 1.0, 1.0),(0.15, 1.0, 1.0), (0.3, 1.0, 1.0), (0.45, 1.0, 1.0), (0.6, 1.0, 1.0), (0.75, 1.0, 1.0), (0.9, 1.0, 1.0)]
HSV_tuples_dark = [(0., 1.0, 0.5),(0.15, 1.0, 0.5), (0.3, 1.0, 0.5), (0.45, 1.0, 0.5), (0.6, 1.0, 0.5), (0.75, 1.0, 0.5), (0.9, 1.0, 0.5)]
HSV_tuples_v3 = [(0.,0.75, 0.5),(0.15,0.75, 0.5), (0.3,0.75, 0.5), (0.45,0.75, 0.5), (0.6,0.75, 0.5), (0.75,0.75, 0.5), (0.9,0.75, 0.5)]

HSV_tuples =      [(0.15, 1.0, 1.0), (0.3, 1.0, 1.0), (0.45, 1.0, 1.0), (0.6, 1.0, 1.0), (0.75, 1.0, 1.0), (0.9, 1.0, 1.0)]
HSV_tuples_dark = [(0., 1.0, 0.5),(0.15, 1.0, 0.5), (0.3, 1.0, 0.5), (0.45, 1.0, 0.5), (0.6, 1.0, 0.5), (0.75, 1.0, 0.5), (0.9, 1.0, 0.5)]
HSV_tuples_v3 = [(0.3,0.75, 0.5), (0.45,0.75, 0.5), (0.6,0.75, 0.5), (0.75,0.75, 0.5), (0.9,0.75, 0.5)]

RGB_tuples = map(lambda x: colorsys.hsv_to_rgb(*x), HSV_tuples)
RGB_tuples_dark = map(lambda x: colorsys.hsv_to_rgb(*x), HSV_tuples_dark)
RGB_tuples_v3 = map(lambda x: colorsys.hsv_to_rgb(*x), HSV_tuples_v3)

def myFunction(msg):
	rotation = msg.pose.rotation
	quat = numpy.array([rotation.w, rotation.x, rotation.y, rotation.z])
	rpy = transformUtils.quaternionToRollPitchYaw(quat)
	return msg.utime, rpy[2]

def myFunctionBDI(msg):
	quat = numpy.array([msg.orientation[0], msg.orientation[1], msg.orientation[2], msg.orientation[3]])
	rpy = transformUtils.quaternionToRollPitchYaw(quat)
	return msg.utime, rpy[2]



def poseY(msg):
	rotation = msg.pose.rotation
	quat = numpy.array([rotation.w, rotation.x, rotation.y, rotation.z])
	rpy = transformUtils.quaternionToRollPitchYaw(quat)
	return msg.utime, rpy[1]

def poseYBDI(msg):
	quat = numpy.array([msg.orientation[0], msg.orientation[1], msg.orientation[2], msg.orientation[3]])
	rpy = transformUtils.quaternionToRollPitchYaw(quat)
	return msg.utime, rpy[1]




# position plot
addPlot(timeWindow=5, yLimits=[-1.5, 1.5])

addSignalFunction('EST_ROBOT_STATE', myFunction)
# addSignalFunction('EST_ROBOT_STATE_1', myFunction)
addSignalFunction('EST_ROBOT_STATE_ORIGINAL', myFunction)
addSignalFunction('POSE_BODY', myFunctionBDI)
addSignalFunction('POSE_BDI', myFunctionBDI)

addSignalFunction('EST_ROBOT_STATE', poseY)
addSignalFunction('POSE_BDI', poseYBDI)


# velocity plot
addPlot(timeWindow=5, yLimits=[-1.5, 1.5])
addSignal('POSE_BODY', msg.utime, msg.rotation_rate[2])
addSignal('POSE_BODY_ORIGINAL', msg.utime, msg.rotation_rate[2])

addSignal('EST_ROBOT_STATE', msg.utime, msg.twist.angular_velocity.z)
addSignal('POSE_BDI', msg.utime, msg.rotation_rate[2])


addSignal('EST_ROBOT_STATE', msg.utime, msg.twist.angular_velocity.y)
addSignal('POSE_BDI', msg.utime, msg.rotation_rate[1])

addPlot(timeWindow=5, yLimits=[-1.5, 1.5])
addSignal('EST_ROBOT_STATE', msg.utime, msg.twist.linear_velocity.x)
addSignal('POSE_BDI', msg.utime, msg.vel[0])








