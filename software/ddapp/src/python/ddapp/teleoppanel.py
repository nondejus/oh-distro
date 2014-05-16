from PythonQt import QtCore, QtGui, QtUiTools
import ddapp.applogic as app
import ddapp.objectmodel as om
from ddapp.timercallback import TimerCallback
from ddapp import robotstate
from ddapp import visualization as vis
from ddapp import transformUtils
from ddapp import ikplanner

import math
import numpy as np



def addWidgetsToDict(widgets, d):

    for widget in widgets:
        if widget.objectName:
            d[str(widget.objectName)] = widget
        addWidgetsToDict(widget.children(), d)


class WidgetDict(object):

    def __init__(self, widgets):
        addWidgetsToDict(widgets, self.__dict__)


def clearLayout(w):
    children = w.findChildren(QtGui.QWidget)
    for child in children:
        child.delete()



class EndEffectorTeleopPanel(object):

    def __init__(self, panel):
        self.panel = panel
        self.ui = panel.ui
        self.ui.eeTeleopButton.connect('clicked()', self.teleopButtonClicked)
        self.ui.planButton.connect('clicked()', self.planClicked)
        self.ui.fixBaseCheck.connect('clicked()', self.fixBaseChanged)
        self.ui.fixBackCheck.connect('clicked()', self.fixBackChanged)
        self.ui.fixOrientCheck.connect('clicked()', self.fixOrientChanged)
        self.ui.updateIkButton.connect('clicked()', self.onUpdateIkClicked)
        self.ui.interactiveCheckbox.visible = False
        self.ui.updateIkButton.visible = False
        self.ui.eeTeleopSideCombo.connect('currentIndexChanged(const QString&)', self.sideChanged)
        self.constraintSet = None

    def getSide(self):
        return str(self.ui.eeTeleopSideCombo.currentText)

    def getBaseFixed(self):
        return self.ui.fixBaseCheck.checked

    def getBackFixed(self):
        return self.ui.fixBackCheck.checked

    def getOrientFixed(self):
        return self.ui.fixOrientCheck.checked

    def fixBaseChanged(self):
        self.updateConstraints()

    def fixBackChanged(self):
        self.updateConstraints()

    def fixOrientChanged(self):
        self.updateConstraints()

    def sideChanged(self):
        side = self.getSide()
        if side == 'left':
            om.removeFromObjectModel(self.getGoalFrame('right'))
        elif side == 'right':
            om.removeFromObjectModel(self.getGoalFrame('left'))
        self.createGoalFrames()
        self.updateConstraints()

    def removeGoals(self):
        for side in ['left', 'right']:
            om.removeFromObjectModel(self.getGoalFrame(side))

    def getGoalFrame(self, side):
        return om.findObjectByName('reach goal %s' % side)

    def updateGoalFrame(self, transform, side):
        goalFrame = self.getGoalFrame(side)
        if not goalFrame:
            return

        if transform is not None:
            goalFrame.copyFrame(transform)
        else:
            goalFrame.transform.Modified()

        return goalFrame


    def onGoalFrameModified(self, frame):
        if self.constraintSet and self.ui.interactiveCheckbox.checked:
            self.updateIk()

    def onUpdateIkClicked(self):
        self.updateIk()

    def updateIk(self):
        self.constraintSet.runIk()
        self.panel.showPose(self.constraintSet.endPose)


    def updateConstraints(self):

        if not self.ui.eeTeleopButton.checked:
            return


        side = self.getSide()
        lockBack = self.getBackFixed()
        lockBase = self.getBaseFixed()
        lockOrient = self.getOrientFixed()

        ikPlanner = self.panel.ikPlanner

        startPoseName = 'reach_start'
        startPose = np.array(self.panel.robotStateJointController.q)
        ikPlanner.addPose(startPose, startPoseName)

        constraints = ikPlanner.createMovingBodyConstraints(startPoseName, lockBack=lockBack, lockBase=lockBase, lockLeftArm=side=='right', lockRightArm=side=='left')

        sides = ['left', 'right'] if side == 'both' else [side]

        for side in sides:
            goalFrame = self.getGoalFrame(side)
            assert goalFrame
            constraintSet = ikPlanner.newReachGoal(startPoseName, side, goalFrame, constraints, lockOrient=lockOrient)
            self.constraintSet = constraintSet

        self.onGoalFrameModified(None)


    def planClicked(self):
        if not self.ui.eeTeleopButton.checked:
            return

        self.generatePlan()

    def generatePlan(self):

        self.updateConstraints()
        #plan = self.constraintSet.runIkTraj()
        plan = self.constraintSet.planEndPoseGoal()
        self.panel.showPlan(plan)

    def teleopButtonClicked(self):
        if self.ui.eeTeleopButton.checked:
            self.activate()
        else:
            self.deactivate()

    def activate(self):
        self.ui.eeTeleopButton.blockSignals(True)
        self.ui.eeTeleopButton.checked = True
        self.ui.eeTeleopButton.blockSignals(False)
        self.panel.endEffectorTeleopActivated()

        self.createGoalFrames()
        self.updateConstraints()


    def deactivate(self):
        self.ui.eeTeleopButton.blockSignals(True)
        self.ui.eeTeleopButton.checked = False
        self.ui.eeTeleopButton.blockSignals(False)
        self.removeGoals()
        self.panel.endEffectorTeleopDeactivated()


    def createGoalFrames(self):

        def addHandMesh(handModel, goalFrame):

            handObj = handModel.newPolyData('reach goal left hand', self.panel.teleopRobotModel.views[0], parent=goalFrame)
            handFrame = handObj.children()[0]
            handFrame.copyFrame(frame.transform)

            frameSync = vis.FrameSync()
            frameSync.addFrame(frame)
            frameSync.addFrame(handFrame)
            frame.sync = frameSync

        handModels = {'left':self.panel.lhandModel, 'right':self.panel.rhandModel}

        ikPlanner = self.panel.ikPlanner

        side = self.getSide()
        sides = ['left', 'right'] if side == 'both' else [side]

        startPose = np.array(self.panel.robotStateJointController.q)

        for side in sides:
            if self.getGoalFrame(side):
                continue

            #startPose = ikPlanner.getMergedPostureFromDatabase(startPose, 'General', 'arm up pregrasp', side)

            t = ikPlanner.newGraspToWorldFrame(startPose, side, ikPlanner.getPalmToHandLink(side))
            frameName = 'reach goal %s' % side
            om.removeFromObjectModel(om.findObjectByName(frameName))
            frame = vis.showFrame(t, frameName, scale=0.2, parent=om.getOrCreateContainer('planning'))
            frame.setProperty('Edit', True)
            frame.connectFrameModified(self.onGoalFrameModified)
            addHandMesh(handModels[side], frame)


    def newReachTeleop(self, frame, side):
        self.panel.jointTeleop.deactivate()

        self.deactivate()
        self.ui.fixBaseCheck.checked = False
        self.ui.fixBackCheck.checked = False
        self.ui.fixOrientCheck.checked = True
        self.ui.eeTeleopSideCombo.setCurrentIndex(self.ui.eeTeleopSideCombo.findText(side))

        self.activate()
        return self.updateGoalFrame(frame, side)


inf = np.inf

class JointTeleopPanel(object):


    jointLimitsMin = [-inf, -inf, -inf, -inf, -inf, -inf, -0.663225, -0.262, -0.698132, -1.5708, -1.5708, 0.0, 0.0, 0.0, -0.174533, -0.523599, -1.72072, 0.0, -1.0, -0.8, -1.1781, -1.5708, -1.5708, 0.0, -2.35619, 0.0, -1.22173, -0.523599, -1.72072, 0.0, -1.0, -0.8, -1.1781, -0.602139]
    jointLimitsMax = [inf, inf, inf, inf, inf, inf, 0.663225, 0.524, 0.698132, 0.785398, 1.5708, 3.14159, 2.35619, 3.14159, 1.22173, 0.523599, 0.524821, 2.38569, 0.7, 0.8, 1.1781, 0.785398, 1.5708, 3.14159, 0.0, 3.14159, 0.174533, 0.523599, 0.524821, 2.38569, 0.7, 0.8, 1.1781, 1.14494]

    jointNames = ['base_x', 'base_y', 'base_z', 'base_roll', 'base_pitch', 'base_yaw', 'back_bkz', 'back_bky', 'back_bkx', 'l_arm_usy', 'l_arm_shx', 'l_arm_ely', 'l_arm_elx', 'l_arm_uwy', 'l_leg_hpz', 'l_leg_hpx', 'l_leg_hpy', 'l_leg_kny', 'l_leg_aky', 'l_leg_akx', 'l_arm_mwx', 'r_arm_usy', 'r_arm_shx', 'r_arm_ely', 'r_arm_elx', 'r_arm_uwy', 'r_leg_hpz', 'r_leg_hpx', 'r_leg_hpy', 'r_leg_kny', 'r_leg_aky', 'r_leg_akx', 'r_arm_mwx', 'neck_ay']

    def __init__(self, panel):
        self.panel = panel
        self.ui = panel.ui
        self.ui.jointTeleopButton.connect('clicked()', self.teleopButtonClicked)
        self.ui.resetJointsButton.connect('clicked()', self.resetButtonClicked)
        self.ui.planButton.connect('clicked()', self.planClicked)

        self.timerCallback = TimerCallback()
        self.timerCallback.callback = self.onTimerCallback

        self.slidersMap = {
            'back_bkx' : self.ui.backRollSlider,
            'back_bky' : self.ui.backPitchSlider,
            'back_bkz' : self.ui.backYawSlider,

            'l_leg_kny' : self.ui.leftKneeSlider,
            'r_leg_kny' : self.ui.rightKneeSlider,

            'l_arm_usy' : self.ui.leftShoulderXSlider,
            'l_arm_shx' : self.ui.leftShoulderYSlider,
            'l_arm_ely' : self.ui.leftShoulderZSlider,
            'l_arm_elx' : self.ui.leftElbowSlider,
            'l_arm_uwy' : self.ui.leftWristXSlider,
            'l_arm_mwx' : self.ui.leftWristYSlider,

            'r_arm_usy' : self.ui.rightShoulderXSlider,
            'r_arm_shx' : self.ui.rightShoulderYSlider,
            'r_arm_ely' : self.ui.rightShoulderZSlider,
            'r_arm_elx' : self.ui.rightElbowSlider,
            'r_arm_uwy' : self.ui.rightWristXSlider,
            'r_arm_mwx' : self.ui.rightWristYSlider,
            }

        self.labelMap = {
            self.ui.backRollSlider : self.ui.backRollLabel,
            self.ui.backPitchSlider : self.ui.backPitchLabel,
            self.ui.backYawSlider : self.ui.backYawLabel,

            self.ui.leftKneeSlider : self.ui.leftKneeLabel,
            self.ui.rightKneeSlider : self.ui.rightKneeLabel,

            self.ui.leftShoulderXSlider : self.ui.leftShoulderXLabel,
            self.ui.leftShoulderYSlider : self.ui.leftShoulderYLabel,
            self.ui.leftShoulderZSlider : self.ui.leftShoulderZLabel,
            self.ui.leftElbowSlider : self.ui.leftElbowLabel,
            self.ui.leftWristXSlider : self.ui.leftWristXLabel,
            self.ui.leftWristYSlider : self.ui.leftWristYLabel,

            self.ui.rightShoulderXSlider : self.ui.rightShoulderXLabel,
            self.ui.rightShoulderYSlider : self.ui.rightShoulderYLabel,
            self.ui.rightShoulderZSlider : self.ui.rightShoulderZLabel,
            self.ui.rightElbowSlider : self.ui.rightElbowLabel,
            self.ui.rightWristXSlider : self.ui.rightWristXLabel,
            self.ui.rightWristYSlider : self.ui.rightWristYLabel,
            }

        self.signalMapper = QtCore.QSignalMapper()

        for jointName, slider in self.slidersMap.iteritems():
            slider.connect('valueChanged(int)', self.signalMapper, 'map()')
            self.signalMapper.setMapping(slider, jointName)

        self.signalMapper.connect('mapped(const QString&)', self.sliderChanged)

        self.startPose = None
        self.endPose = None
        self.userJoints = {}

        self.updateWidgetState()


    def planClicked(self):
        if not self.ui.jointTeleopButton.checked:
            return

        self.computeEndPose()
        self.generatePlan()


    def generatePlan(self):
        plan = self.panel.ikPlanner.computePostureGoal(self.startPose, self.endPose)
        self.panel.showPlan(plan)


    def teleopButtonClicked(self):
        if self.ui.jointTeleopButton.checked:
            self.activate()
        else:
            self.deactivate()


    def activate(self):
        self.timerCallback.stop()
        self.panel.jointTeleopActivated()
        self.resetPose()
        self.updateWidgetState()


    def deactivate(self):
        self.timerCallback.stop()
        self.panel.jointTeleopDeactivated()
        self.updateWidgetState()


    def updateWidgetState(self):

        enabled = self.ui.jointTeleopButton.checked

        for slider in self.slidersMap.values():
            slider.setEnabled(enabled)

        self.ui.resetJointsButton.setEnabled(enabled)

        if not enabled:
            self.timerCallback.start()


    def resetButtonClicked(self):
        self.resetPose()
        self.panel.showPose(self.endPose)

    def resetPose(self):
        self.userJoints = {}
        self.computeEndPose()
        self.updateSliders()

    def onTimerCallback(self):
        if not self.ui.tabWidget.visible:
            return
        self.resetPose()

    def toJointIndex(self, jointName):
        return robotstate.getDrakePoseJointNames().index(jointName)

    def toJointName(self, jointIndex):
        return robotstate.getDrakePoseJointNames()[jointIndex]

    def toJointValue(self, jointIndex, sliderValue):
        assert 0.0 <= sliderValue <= 1.0
        jointRange = self.jointLimitsMin[jointIndex], self.jointLimitsMax[jointIndex]
        return jointRange[0] + (jointRange[1] - jointRange[0])*sliderValue

    def toSliderValue(self, jointIndex, jointValue):
        jointRange = self.jointLimitsMin[jointIndex], self.jointLimitsMax[jointIndex]
        #if jointValue < jointRange[0] or jointValue > jointRange[1]:
        #    print 'warning: joint %s value %f is out of expected range [%f, %f]' % (self.toJointName(jointIndex), jointValue, jointRange[0], jointRange[1])
        return (jointValue - jointRange[0]) / (jointRange[1] - jointRange[0])

    def getSlider(self, joint):
        jointName = self.toJointName(joint) if isinstance(joint, int) else joint
        return self.slidersMap[jointName]

    def computeEndPose(self):

        self.startPose = np.array(self.panel.robotStateJointController.q)
        self.endPose = self.startPose.copy()

        hasKnee = False
        for jointIndex, jointValue in self.userJoints.iteritems():
            self.endPose[jointIndex] = jointValue
            if 'kny' in self.toJointName(jointIndex):
                hasKnee = True

        if hasKnee:

            ikPlanner = self.panel.ikPlanner

            startPoseName = 'posture_goal_start'
            ikPlanner.addPose(self.startPose, startPoseName)

            endPoseName = 'posture_goal_end'
            ikPlanner.addPose(self.endPose, endPoseName)

            jointNames = self.slidersMap.keys()
            p = ikPlanner.createPostureConstraint(endPoseName, jointNames)

            constraints = [p]
            constraints.extend(ikPlanner.createFixedFootConstraints(startPoseName))
            constraints.append(ikPlanner.createMovingBasePostureConstraint(startPoseName))

            self.endPose, info = ikPlanner.ikServer.runIk(constraints, seedPostureName=startPoseName)


    def getJointValue(self, jointIndex):
        return self.endPose[jointIndex]


    def sliderChanged(self, jointName):

        slider = self.slidersMap[jointName]
        jointIndex = self.toJointIndex(jointName)
        jointValue = self.toJointValue(jointIndex, slider.value / 99.0)

        self.userJoints[jointIndex] = jointValue

        if 'kny' in jointName:
            self.userJoints[self.toJointIndex('r_leg_kny')] = jointValue
            self.userJoints[self.toJointIndex('l_leg_kny')] = jointValue
            self.updateSliders()

        self.computeEndPose()
        self.panel.showPose(self.endPose)
        self.updateLabels()


    def updateLabels(self):

        for jointName, slider in self.slidersMap.iteritems():
            jointIndex = self.toJointIndex(jointName)
            jointValue = self.getJointValue(jointIndex)
            label = self.labelMap[slider]
            label.text = str('%.1f' % math.degrees(jointValue)).center(5, ' ')

    def updateSliders(self):

        for jointName, slider in self.slidersMap.iteritems():
            jointIndex = self.toJointIndex(jointName)
            jointValue = self.getJointValue(jointIndex)

            slider.blockSignals(True)
            slider.setValue(self.toSliderValue(jointIndex, jointValue)*99)
            slider.blockSignals(False)

        self.updateLabels()


class TeleopPanel(object):

    def __init__(self, robotStateModel, robotStateJointController, teleopRobotModel, teleopJointController, ikPlanner, manipPlanner, lhandModel, rhandModel, showPlanFunction):

        self.robotStateModel = robotStateModel
        self.robotStateJointController = robotStateJointController
        self.teleopRobotModel = teleopRobotModel
        self.teleopJointController = teleopJointController
        self.lhandModel = lhandModel
        self.rhandModel = rhandModel
        self.ikPlanner = ikPlanner
        self.manipPlanner = manipPlanner
        self.showPlanFunction = showPlanFunction

        loader = QtUiTools.QUiLoader()
        uifile = QtCore.QFile(':/ui/ddTeleopPanel.ui')
        assert uifile.open(uifile.ReadOnly)

        self.widget = loader.load(uifile)
        uifile.close()

        self.ui = WidgetDict(self.widget.children())
        self.ui.postureDatabaseButton.connect('clicked()', self.onPostureDatabaseClicked)

        self.endEffectorTeleop = EndEffectorTeleopPanel(self)
        self.jointTeleop = JointTeleopPanel(self)

    def onPostureDatabaseClicked(self):
        ikplanner.RobotPoseGUIWrapper.show()

    def disableJointTeleop(self):
        self.ui.jointTeleopFrame.setEnabled(False)

    def disableEndEffectorTeleop(self):
        self.ui.endEffectorTeleopFrame.setEnabled(False)

    def jointTeleopActivated(self):
        self.disableEndEffectorTeleop()

    def endEffectorTeleopActivated(self):
        self.disableJointTeleop()

    def endEffectorTeleopDeactivated(self):
        self.hideTeleopModel()
        self.enablePanels()

    def jointTeleopDeactivated(self):
        self.hideTeleopModel()
        self.enablePanels()

    def enablePanels(self):
        self.ui.endEffectorTeleopFrame.setEnabled(True)
        self.ui.jointTeleopFrame.setEnabled(True)

    def hideTeleopModel(self):
        self.teleopRobotModel.setProperty('Visible', False)
        self.robotStateModel.setProperty('Visible', True)
        self.robotStateModel.setProperty('Alpha', 1.0)

    def showTeleopModel(self):
        self.teleopRobotModel.setProperty('Visible', True)
        self.robotStateModel.setProperty('Visible', True)
        self.robotStateModel.setProperty('Alpha', 0.1)

    def showPose(self, pose):
        self.teleopJointController.setPose('teleop_pose', pose)
        self.showTeleopModel()

    def showPlan(self, plan):
        self.hideTeleopModel()
        self.showPlanFunction(plan)


def _getAction():
    return app.getToolBarActions()['ActionTeleopPanel']


def init(robotStateModel, robotStateJointController, teleopRobotModel, teleopJointController, debrisPlanner, manipPlanner, lhandModel, rhandModel, showPlanFunction):

    global panel
    global dock

    panel = TeleopPanel(robotStateModel, robotStateJointController, teleopRobotModel, teleopJointController, debrisPlanner, manipPlanner, lhandModel, rhandModel, showPlanFunction)
    dock = app.addWidgetToDock(panel.widget, action=_getAction())
    dock.hide()

    return panel
