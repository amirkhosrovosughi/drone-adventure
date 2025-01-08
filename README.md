# Drone Adventure Project

Personal project to develop multi-agent localization and path planning tools for drone


## requirement
- Ubuntu-22.04
- ROS2 Humble
- install 
<pre>
sudo apt install ros-humble-ros-gzgardenra
</pre>

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

Make these changes on PX4-Autopilot:

1 - In `PX4-Autopilot/src/modules/simulation/gz_bridge/gz_env.sh.in` line 4 change
<pre>
export PX4_GZ_WORLDS=@PX4_SOURCE_DIR@/Tools/simulation/gz/worlds
</pre>
to
<pre>
export PX4_GZ_WORLDS=@PX4_SOURCE_DIR@/../drone_ws/src/drone_packages/simulation_resource/worlds
</pre>

2 - In `PX4-Autopilot/Tools/simulation/gz/models/x500_depth/model.sdf`, line , change from
```xml
<pose>.12 .03 .242 0 0 0</pose>
```
to
```xml
<pose>.12 .03 .242 0 0.785 0</pose>
```

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
Open 4 terminals.
In terminal 1 run PX4 drone simulator:
<pre>
cd ~/drone-adventure/PX4-Autopilot
make px4_sitl gz_x500_depth
</pre>

In terminal 2:
<pre>
MicroXRCEAgent udp4 -p 8888
</pre>

In terminal 3:
<pre>
source ~/drone-adventure/drone_ws/install/setup.bash
ros2 launch drone_launch drone_launch.py
</pre>

Above launch file is equivalent of running below ros nodes:
<pre>
ros2 run ros_gz_image image_bridge /camera
ros2 run ros_gz_image image_bridge /depth_camera
ros2 run px4_command_handler px4_command_handler
ros2 run visual_feature_extraction visual_feature_extraction
</pre>

image_bridge nodes provides gazeboo camera info as ros2 topic. To see the camera image, you can run below command and select /camera or /depth_camera topic
<pre>
ros2 run rqt_image_view rqt_image_view
</pre> 
px4_command_handler node listen to teleop and send commands to drone simulator through MicroXRCEAgent.
visual_feature_extraction node publish topic /featureDetection/coordinate that shows relative position of the detected feature in the photo and corresponding depth. You can change option DEBUG_FEATURE to ON to visualize the detected features.  

In terminal 4:
<pre>
source ~/drone-adventure/drone_ws/install/setup.bash
ros2 run keyboard_control keyboard_control_node
</pre>

Now, you should be able to control the drone's movement. To start the drone, press '1' to arm the drone first.

**Controls:**
- Press 'w' to ascend
- Press 's' to descend
- Press 'a' to rotate anti-clockwise
- Press 'd' to rotate clockwise

- Press 'u' to move forwards
- Press 'j' to move backwards
- Press 'h' to move left
- Press 'k' to move right

- Press '+' to increase speed
- Press '-' to decrease speed

- Press 'c' to enter cli command of movement of the robot and then press Eneter to run the command.
  below is the list of the commands:

  - **`nomove`**: The robot remains stationary (no movement).  
  - **`gottoorigin`**: Moves the robot to the origin coordinates (0, 0) and hovers at 2 meters.  
  - **`goto <x_coordinate> <y_coordinate> <z_coordinate> <heading_angle>`**: Moves the robot to an arbitrary point. You must provide four arguments:  
    - `x_coordinate`: Target x-coordinate.  
    - `y_coordinate`: Target y-coordinate.  
    - `z_coordinate`: Target z-coordinate.  
    - `heading_angle`: Desired heading angle in radians.  
  - **`headto <heading_angle>`**: Rotates the robot to the specified heading angle (in radians).  
  - **`headfw`**: Rotates the robot to face forward (`0` radians).  
  - **`headbw`**: Rotates the robot to face backward (`π` radians).  
  - **`headleft`**: Rotates the robot to face left (`-π/2` radians).  
  - **`headright`**: Rotates the robot to face right (`+π/2` radians).

Feel free to adjust and customize the controls according to your preferences.

In terminal 5:
You can run SLAM node, this module is still in progress and has not been finalized yet.
<pre>
ros2 run slam slam
</pre>

# already added, need to 
Next to be completed:
- SLAM
- Visualization
