# Drone Adventure Project

Personal project to develop multi-agent localization and path-planning tools for drones.


## Requirements
- Ubuntu 22.04
- ROS2 Humble
- Install:
<pre>
sudo apt install ros-humble-ros-gzgarden
</pre>

## Installation
First, clone the repository:

<pre>
sudo apt update
git clone https://github.com/amirkhosrovosughi/drone-adventure.git
cd drone-adventure
git submodule update --init --recursive
</pre>


### Install PX4-Autopilot
<pre>
bash ./PX4-Autopilot/Tools/setup/ubuntu.sh
cd PX4-Autopilot/
make px4_sitl
</pre>

Make these changes in `PX4-Autopilot`:

1. In `PX4-Autopilot/src/modules/simulation/gz_bridge/gz_env.sh.in`, line 4, change:
<pre>
export PX4_GZ_WORLDS=@PX4_SOURCE_DIR@/Tools/simulation/gz/worlds
</pre>
to:
<pre>
export PX4_GZ_WORLDS=@PX4_SOURCE_DIR@/../drone_ws/src/drone_packages/simulation_resource/worlds
</pre>

2. In `PX4-Autopilot/Tools/simulation/gz/models/x500_depth/model.sdf`, update the camera pose from:
```xml
<pose>.12 .03 .242 0 0 0</pose>
```
to
```xml
<pose>.12 .03 .242 0 0.785 0</pose>
```

### Install Micro-XRCE-DDS-Agent
<pre>
cd Micro-XRCE-DDS-Agent
mkdir build
cd build
cmake ..
make
sudo make install
sudo ldconfig /usr/local/lib/
</pre>

### Build ROS Packages
<pre>
cd drone_ws
source /opt/ros/humble/setup.bash
colcon build
</pre>

## Running Unit Tests
<pre>
colcon build --cmake-args -DBUILD_TESTING=ON
colcon test
colcon test-result --verbose
</pre>

Hint: use `--packages-select` to build or test a specific package. For example:
<pre>
colcon build --packages-select common_utilities --cmake-args -DBUILD_TESTING=ON
</pre>

## Environment Setup
Before running the simulation, make sure Gazebo can find your custom models.

From the **root of the project**, run the following command to add your `simulation_resource/models` folder to the Gazebo model path:
<pre>
echo "export GZ_SIM_RESOURCE_PATH=$(pwd)/drone_ws/src/drone_packages/simulation_resource/models:\$GZ_SIM_RESOURCE_PATH" >> ~/.bashrc
source ~/.bashrc
</pre>

## Run
Open 3 terminals.
In terminal 1, run the PX4 drone simulator script:
<pre>
./run_drone_sim.sh
</pre>


This script performs the same startup sequence as the following commands and ensures the world is ready before spawning PX4 (to avoid startup race conditions):
<pre>
cd ~/drone-adventure/PX4-Autopilot
make px4_sitl gz_x500_depth
</pre>

<pre>
MicroXRCEAgent udp4 -p 8888
</pre>

If startup fails, a previous simulation process may still be running. In that case, run this cleanup script:
<pre>
./stop_drone_sim.sh
</pre>

In terminal 2:
<pre>
source ~/drone-adventure/drone_ws/install/setup.bash
ros2 launch drone_launch drone_launch.py
</pre>

The launch file above is equivalent to running these ROS2 nodes:
<pre>
ros2 run ros_gz_image image_bridge /camera
ros2 run ros_gz_image image_bridge /depth_camera
ros2 run px4_command_handler px4_command_handler
ros2 run visual_feature_extraction visual_feature_extraction
ros2 run slam slam
</pre>

`image_bridge` nodes provide Gazebo camera streams as ROS2 topics. To view the camera image, run the command below and select `camera` or `/depth_camera`:
<pre>
ros2 run rqt_image_view rqt_image_view
</pre> 
`px4_command_handler` listens to teleop commands and sends commands to the drone simulator through MicroXRCEAgent.

In terminal 3:
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

- Press 'c' to enter a movement CLI command, then press Enter to run it.
  Available commands:

  - **`nomove`**: The robot remains stationary (no movement).  
  - **`gotoorigin`**: Moves the robot to the origin coordinates (0, 0) and hovers at 2 meters.  
  - **`goto <x_coordinate> <y_coordinate> <z_coordinate> <heading_angle>`**: Moves the robot to an arbitrary point. You must provide four arguments:  
    - `x_coordinate`: Target x-coordinate.  
    - `y_coordinate`: Target y-coordinate.  
    - `z_coordinate`: Target z-coordinate.  
    - `heading_angle`: Desired heading angle in radians.  
  - **`headto <heading_angle>`**: Rotates the robot to the specified heading angle (in radians).  
  - **`headfw`**: Rotates the robot to face forward (`0` radians).  
  - **`headbw`**: Rotates the robot to face backward (`π` radians).  
  - **`headleft`**: Rotates the robot to face left (`+π/2` radians).  
  - **`headright`**: Rotates the robot to face right (`-π/2` radians).

Feel free to adjust and customize the controls according to your preferences.


If you want to see visualization of SLAM, in a new terminal run
<pre>
 ros2 launch slam_visualization slam_visualization_launch.py
</pre>

Then select the `/visualization_marker` topic in the opened RViz window.

## Diagnostics and Build Options
### Logging runtime data in CSV format
If you build the project with the `STORE_DEBUG_DATA` flag, you can log values during runtime.
Example:
<pre>
#ifdef STORE_DEBUG_DATA
  data_logging_utils::DataLogger::log("robotPose.position.x", _robotPose.position.x);
#endif
</pre>

By default, logs are written to `~/ros_data_logging` in a timestamped folder created when the simulation starts. This is useful for plotting signals and debugging algorithms.
You can use scirpt `data_logging_utils/scripts/plot_data_logger.py` for plotting the data. See the documentation on that script for instruction on how to use it.

### Compile-time flag options
You can pass compile-time flags to change package behavior.

#### `slam` package options
You can enable one SLAM algorithm implementation:
- `SLAM_EKF`: Extended Kalman Filter (EKF) SLAM
- `SLAM_GRAPH`: Least-squares graph-based SLAM
- `SLAM_FAST_SLAM`: Particle filter-based FastSLAM

Example:
<pre>
colcon build --packages-select slam --cmake-args -DSLAM_EKF=ON
</pre>

If no SLAM flag is provided, `SLAM_EKF` is used by default.

#### `feature_2dto3d_transfer` package options
You can choose which feature topic(s) this package publishes (used by `slam` as observation input):
- `ONLY_BBOX`: publish only bounding-box coordinates in the image frame
- `ONLY_3D_POINT`: publish only extracted 3D points for detections with valid depth, and ignore detections without depth

If no flag is provided, both topics are published: 3D coordinates when depth is available, otherwise bounding boxes.

Tip: run a clean build when switching compile-time options.

### Monitoring system resources
To monitor machine resources, run the script below in a new terminal. It reports CPU, GPU, and memory usage during execution, including average and peak values at the end.

<pre>
./monitor_resources.sh
</pre>


## Documentation
To explore the documentation, open this file in your browser after generating the docs:

[📖 Open Documentation (index.html)](drone_ws/doc/html/index.html)

### Update or Regenerate Documentation
<pre>
cd ~/drone-adventure/drone_ws/
cmake -S . -B build-docs
cmake --build build-docs --target doc_doxygen
</pre>

## Next To Be Completed
- Autonomous drone movement using RL to generate a map and localize falut within it

## Install ONNX Runtime for Deep Object Detection
<pre>
cd ~
wget https://github.com/microsoft/onnxruntime/releases/download/v1.19.0/onnxruntime-linux-x64-1.19.0.tgz

tar -xzf onnxruntime-linux-x64-1.19.0.tgz
mv ~/onnxruntime-linux-x64-1.19.0 ~/onnxruntime

echo 'export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/onnxruntime/lib' >> ~/.bashrc
source ~/.bashrc
</pre>