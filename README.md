# Drone Adventure Project

Personal project to develop multi-agent localization and path planning tools for drone


## requirement
- Ubuntu-22.04
- ROS2 Humble

## installation:
First clone the repo

<pre>
sudo apt update
git clone https://github.com/amirkhosrovosughi/drone-adventure.git
git submodule update --init --recursive
</pre>


### install PX4-Autopilot
<pre>
bash ./PX4-Autopilot/Tools/setup/ubuntu.sh
cd PX4-Autopilot/
make px4_sitl
</pre>

### install Micro-XRCE-DDS-Agent
<pre>
cd Micro-XRCE-DDS-Agent
mkdir build
cd build
cmake ..
make
sudo make install
sudo ldconfig /usr/local/lib/
</pre>

### build ROS packages
 <pre>
cd drone_ws
source /opt/ros/humble/setup.bash
colcon build
 </pre>

## run
Open three terminals.
In terminal 1:
<pre>
MicroXRCEAgent udp4 -p 8888
</pre>

In terminal 2:
<pre>
cd ~/drone-adventure/PX4-Autopilot
make px4_sitl gz_x500
</pre>

In terminal 3:
<pre>
source ~/drone-adventure/drone_ws/install/setup.bash
roslaunch drone_control keyboard_teleop
</pre>
