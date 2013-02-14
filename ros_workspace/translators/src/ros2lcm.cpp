// Selective ros2lcm translator
// mfallon aug,sept 2012

#include <boost/thread.hpp>
#include <boost/shared_ptr.hpp>


#include <ros/ros.h>
#include <ros/console.h>
#include <cstdlib>
#include <sys/time.h>
#include <time.h>
#include <iostream>

#include <message_filters/subscriber.h>
#include <message_filters/time_synchronizer.h>
#include <message_filters/synchronizer.h>
#include <message_filters/sync_policies/approximate_time.h>
#include <image_transport/image_transport.h>
#include <image_transport/subscriber_filter.h>
#include <image_geometry/stereo_camera_model.h>

#include <sensor_msgs/image_encodings.h>
#include <cv_bridge/cv_bridge.h>


#include <sensor_msgs/LaserScan.h>
#include <sensor_msgs/Image.h>
#include <sensor_msgs/CameraInfo.h>
#include <sensor_msgs/Imu.h>
#include <atlas_gazebo_msgs/RobotState.h>
#include <rosgraph_msgs/Clock.h>

#include <lcm/lcm-cpp.hpp>
#include <lcmtypes/bot_core.hpp>
#include <lcmtypes/drc_lcmtypes.hpp>
#include <ros/callback_queue.h>

#define VERBOSE false
using namespace std;


int width =1024; // hardcoded
int height =544; // hardcoded
uint8_t* stereo_data = new uint8_t [2*3* width*height]; // 2 color scale images stacked
uint8_t* singleimage_data = new uint8_t [2*2* width*height]; // 1 color scale image

class App{
public:
  App(const std::string & stereo_in, const std::string & stereo_out, ros::NodeHandle node_);
  ~App();

private:
  lcm::LCM lcm_publish_ ;
  ros::NodeHandle node_;
  
  // Clock:
  ros::Subscriber clock_sub_;
  void clock_cb(const rosgraph_msgs::ClockConstPtr& msg);
  
  // Robot State:
  ros::Subscriber rstate_sub_;
  void rstate_cb(const atlas_gazebo_msgs::RobotStateConstPtr& msg);
  
  // Imu:
  ros::Subscriber torso_imu_sub_,head_imu_sub_;
  void torso_imu_cb(const sensor_msgs::ImuConstPtr& msg);
  void head_imu_cb(const sensor_msgs::ImuConstPtr& msg);
  void send_imu(const sensor_msgs::ImuConstPtr& msg,string channel );
  void send_imu_as_pose(const sensor_msgs::ImuConstPtr& msg,string channel );

  // Laser:
  void send_lidar(const sensor_msgs::LaserScanConstPtr& msg,string channel );
  ros::Subscriber rotating_scan_sub_;
  void rotating_scan_cb(const sensor_msgs::LaserScanConstPtr& msg);
  // porterbot:
  ros::Subscriber scan_left_sub_,scan_right_sub_; // porterbot
  void scan_left_cb(const sensor_msgs::LaserScanConstPtr& msg);
  void scan_right_cb(const sensor_msgs::LaserScanConstPtr& msg);

  // Left and Right Images Seperately:
  void left_image_cb(const sensor_msgs::ImageConstPtr& msg);
  void right_image_cb(const sensor_msgs::ImageConstPtr& msg);
  ros::Subscriber left_image_sub_,right_image_sub_;
  void send_image(const sensor_msgs::ImageConstPtr& msg,string channel );

  // Combined Stereo Image:
  void stereo_cb(const sensor_msgs::ImageConstPtr& l_image,
      const sensor_msgs::CameraInfoConstPtr& l_cam_info,
      const sensor_msgs::ImageConstPtr& r_image,
      const sensor_msgs::CameraInfoConstPtr& r_cam_info);
  image_transport::ImageTransport it_;
  image_transport::SubscriberFilter l_image_sub_, r_image_sub_;
  message_filters::Subscriber<sensor_msgs::CameraInfo> l_info_sub_, r_info_sub_;
  message_filters::TimeSynchronizer<sensor_msgs::Image, sensor_msgs::CameraInfo,
  sensor_msgs::Image, sensor_msgs::CameraInfo> sync_;
  const std::string stereo_in_,stereo_out_;
};

App::App(const std::string & stereo_in,
    const std::string & stereo_out,
    ros::NodeHandle node_) :
    stereo_in_(stereo_in),
    stereo_out_(stereo_out),
    node_(node_),
    it_(node_),
    sync_(10) {
  ROS_INFO("Initializing Translator");

  if(!lcm_publish_.good()){
    std::cerr <<"ERROR: lcm is not good()" <<std::endl;
  }

  // Clock:  
  clock_sub_ = node_.subscribe(string("/clock"), 10, &App::clock_cb,this);

  // IMU:
  torso_imu_sub_ = node_.subscribe(string("/atlas/imu"), 10, &App::torso_imu_cb,this);
  head_imu_sub_ = node_.subscribe(string("/multisense_sl/imu"), 10, &App::head_imu_cb,this);
  
  // Laser:
  rotating_scan_sub_ = node_.subscribe(string("/multisense_sl/laser/scan"), 10, &App::rotating_scan_cb,this);
  // Porterbot
  scan_left_sub_ = node_.subscribe(string("/scan_left"), 10, &App::scan_left_cb,this);
  scan_right_sub_ = node_.subscribe(string("/scan_right"), 10, &App::scan_right_cb,this);

  // Robot State:
  rstate_sub_ = node_.subscribe("true_robot_state", 1000, &App::rstate_cb,this, ros::TransportHints().unreliable().maxDatagramSize(1000).tcpNoDelay());
//  rstate_sub_ = node_.subscribe("true_robot_state", 10, &App::rstate_cb,this);

  cout << "sin :" << stereo_in_ << "sdfsdfsdfsdfsdfssdfsd\n";
  

  // Stereo Image:
  std::string lim_string ,lin_string,rim_string,rin_string;
  int which_image = 4;
  if (which_image==0){ // Grey:
    lim_string = stereo_in_ + "/left/image_rect";
    lin_string = stereo_in_ + "/left/camera_info";
    rim_string = stereo_in_ + "/right/image_rect";
    rin_string = stereo_in_ + "/right/camera_info";
  }else if(which_image==1){ // Color:
    lim_string = stereo_in_ + "/left/image_rect_color";
    lin_string = stereo_in_ + "/left/camera_info";
    rim_string = stereo_in_ + "/right/image_rect_color";
    rin_string = stereo_in_ + "/right/camera_info";
  }else if(which_image==2){ // Raw:
    lim_string = stereo_in_ + "/left/image_raw";
    lin_string = stereo_in_ + "/left/camera_info";
    rim_string = stereo_in_ + "/right/image_raw";
    rin_string = stereo_in_ + "/right/camera_info";
  }else if(which_image==4){ // Raw on GFE:
    lim_string = stereo_in_ + "/left/image_raw";
    lin_string = stereo_in_ + "/left/camera_info";
    rim_string = stereo_in_ + "/right/image_raw";
    rin_string = stereo_in_ + "/right/camera_info";
  }else{
    cout << "Image choice not supported!\n";
    exit(-1); 
  }
  cout << lim_string << " is the left stereo image subscription [for stereo]\n";
  l_image_sub_.subscribe(it_, ros::names::resolve( lim_string ), 3);
  l_info_sub_.subscribe(node_, ros::names::resolve( lin_string ), 3);
  r_image_sub_.subscribe(it_, ros::names::resolve( rim_string ), 3);
  r_info_sub_.subscribe(node_, ros::names::resolve( rin_string ), 3);
  sync_.connectInput(l_image_sub_, l_info_sub_, r_image_sub_, r_info_sub_);
  sync_.registerCallback( boost::bind(&App::stereo_cb, this, _1, _2, _3, _4) );
  
  // Mono-Cameras:
  if (1==0){
    left_image_sub_ = node_.subscribe(lim_string, 10, &App::left_image_cb,this);
    right_image_sub_ = node_.subscribe(rim_string, 10, &App::right_image_cb,this);
  }
};

App::~App()  {
}

void App::send_imu(const sensor_msgs::ImuConstPtr& msg,string channel ){
  drc::imu_t imu_msg;
  imu_msg.utime = (int64_t) floor(msg->header.stamp.toNSec()/1000);  
  //imu_msg.frame_id = msg->header->frame_id;
  imu_msg.orientation[0] = msg->orientation.w; // NB: order here is wxyz
  imu_msg.orientation[1] = msg->orientation.x;
  imu_msg.orientation[2] = msg->orientation.y;
  imu_msg.orientation[3] = msg->orientation.z;
  imu_msg.angular_velocity[0] = msg->angular_velocity.x;
  imu_msg.angular_velocity[1] = msg->angular_velocity.y;
  imu_msg.angular_velocity[2] = msg->angular_velocity.z;
  imu_msg.linear_acceleration[0] = msg->linear_acceleration.x;
  imu_msg.linear_acceleration[1] = msg->linear_acceleration.y;
  imu_msg.linear_acceleration[2] = msg->linear_acceleration.z;
  for (size_t i=0;i<9;i++){
    imu_msg.orientation_covariance[i] = msg->orientation_covariance[i];
    imu_msg.angular_velocity_covariance[i] = msg->angular_velocity_covariance[i];
    imu_msg.linear_acceleration_covariance[i] = msg->linear_acceleration_covariance[i];
  }
  lcm_publish_.publish(channel, &imu_msg);
}
void App::send_imu_as_pose(const sensor_msgs::ImuConstPtr& msg,string channel ){
  bot_core::pose_t pose_msg;
  pose_msg.utime = (int64_t) floor(msg->header.stamp.toNSec()/1000);  
  pose_msg.pos[0] = 0;
  pose_msg.pos[1] = 0;
  pose_msg.pos[2] = 0;
  pose_msg.orientation[0] = msg->orientation.w;
  pose_msg.orientation[1] = msg->orientation.x;
  pose_msg.orientation[2] = msg->orientation.y;
  pose_msg.orientation[3] = msg->orientation.z;
  lcm_publish_.publish(channel, &pose_msg);
}

void App::torso_imu_cb(const sensor_msgs::ImuConstPtr& msg){
  send_imu(msg,"TORSO_IMU");
  send_imu_as_pose(msg,"POSE_BODY_ORIENT");
}

void App::head_imu_cb(const sensor_msgs::ImuConstPtr& msg){
  send_imu(msg,"HEAD_IMU");
  send_imu_as_pose(msg,"POSE_HEAD_ORIENT");
}

void App::clock_cb(const rosgraph_msgs::ClockConstPtr& msg){
  drc::utime_t utime_msg;
  utime_msg.utime = (int64_t) floor(msg->clock.toNSec()/1000);
  lcm_publish_.publish("ROBOT_UTIME", &utime_msg);
}

int stereo_counter=0;
void App::stereo_cb(const sensor_msgs::ImageConstPtr& l_image,
    const sensor_msgs::CameraInfoConstPtr& l_cam_info,
    const sensor_msgs::ImageConstPtr& r_image,
    const sensor_msgs::CameraInfoConstPtr& r_cam_info)
{
  
  int64_t current_utime = (int64_t) floor(l_image->header.stamp.toNSec()/1000);
  stereo_counter++;
  if (stereo_counter%30 ==0){
    std::cout << stereo_counter << " stereo images -> CAMERA \n";
  }

  namespace enc = sensor_msgs::image_encodings;
  cv_bridge::CvImageConstPtr left_ptr;
  cv_bridge::CvImageConstPtr right_ptr;
  int isize = l_image->width*l_image->height;

  //cout << l_image->width << " w | h " << l_image->height << "\n";

  bot_core::image_t stereo;
  stereo.utime =current_utime;
  stereo.width =l_image->width;
  stereo.height =2*l_image->height;
  stereo.nmetadata =0;

  if (l_image->encoding.compare("bgr8") == 0){
    // Need to convert image to OpenCV to invert R and B:
    // OpenCV: BGR | LCM: RGB
    int n_colors = 3; // 1 is grey, 3 is rgb
    left_ptr =  cv_bridge::toCvShare(l_image, enc::BGR8);//MONO8);
    right_ptr =  cv_bridge::toCvShare(r_image, enc::BGR8);//MONO8);
    cv::Mat l_img;
    cvtColor( left_ptr->image, l_img, CV_BGR2RGB);
    cv::Mat r_img;
    cvtColor( right_ptr->image, r_img, CV_BGR2RGB);

    // Write to file:
    //cv::imwrite("left.png", left_ptr->image);
    //cv::imwrite("right.png", right_ptr->image);

    stereo.row_stride=n_colors*l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_RGB;
    stereo.size =n_colors *2*isize;
    copy(l_img.data, l_img.data + n_colors*isize, stereo_data);
    copy(r_img.data, r_img.data + n_colors*isize, stereo_data  + (n_colors * isize));
    stereo.data.assign(stereo_data, stereo_data + ( n_colors*2*isize));
  }else if (l_image->encoding.compare("mono8") == 0){
    stereo.row_stride=l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_GRAY;
    stereo.size =2*isize;
    copy(l_image->data.begin(), l_image->data.end(), stereo_data);
    copy(r_image->data.begin(), r_image->data.end(), stereo_data + (l_image->width*l_image->height));
    stereo.data.assign(stereo_data, stereo_data + ( 2*isize));
  }else if (l_image->encoding.compare("bayer_bggr8") == 0){
    stereo.row_stride=l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_BAYER_BGGR;
    stereo.size =2*isize; // I think its the same size as a typical grayscale...
    copy(l_image->data.begin(), l_image->data.end(), stereo_data);
    copy(r_image->data.begin(), r_image->data.end(), stereo_data + (l_image->width*l_image->height));
    stereo.data.assign(stereo_data, stereo_data + ( 2*isize));
  }else if (l_image->encoding.compare("rgb8") == 0){
    // Need to convert image to OpenCV to invert R and B:
    // OpenCV: BGR | LCM: RGB
    int n_colors = 3; // 1 is grey, 3 is rgb
    stereo.row_stride=n_colors*l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_RGB;
    stereo.size =n_colors *2*isize;
    copy(l_image->data.begin(), l_image->data.end(), stereo_data);
    copy(r_image->data.begin(), r_image->data.end(), stereo_data +  n_colors*isize);
    stereo.data.assign(stereo_data, stereo_data + ( n_colors*2*isize));   
  }else{
    cout << l_image->encoding << " image encoded not supported, not publishing\n";
    cout << stereo_out_ << "\n";
    return;
  }
  lcm_publish_.publish(stereo_out_.c_str(), &stereo);
  
  // As a convenience also publish the left image:
  send_image(l_image, "CAMERALEFT" );
}


// typical contents: 640 x 480 images (out of date)
// points: xyz
// channels: rgb u v
int l_counter =0;
void App::left_image_cb(const sensor_msgs::ImageConstPtr& msg){
  l_counter++;
  if (l_counter%30 ==0){
    std::cout << l_counter << " left image\n";
  }  
  send_image(msg, "CAMERALEFT");
}
int r_counter =0;
void App::right_image_cb(const sensor_msgs::ImageConstPtr& msg){
  r_counter++;
  if (r_counter%30 ==0){
    std::cout << r_counter << " right image\n";
  }  
  send_image(msg, "CAMERARIGHT");
}

// TODO: jpeg compression:
//       look into openni_utils/openni_ros2rgb for code
// TODO: pre-allocate image_data and retain for speed - when size is known
void App::send_image(const sensor_msgs::ImageConstPtr& msg,string channel ){
  int64_t current_utime = (int64_t) floor(msg->header.stamp.toNSec()/1000);
  /*cout << msg->width << " " << msg->height << " | "
       << msg->encoding << " is encoding | "
       << current_utime << " | "<< channel << "\n";*/

  int n_colors=3;
  int isize = msg->width*msg->height;

  bot_core::image_t lcm_img;
  lcm_img.utime =current_utime;
  lcm_img.width =msg->width;
  lcm_img.height =msg->height;
  lcm_img.nmetadata =0;
  lcm_img.row_stride=n_colors*msg->width;
  lcm_img.pixelformat =bot_core::image_t::PIXEL_FORMAT_RGB;
  lcm_img.size =n_colors*isize;
  copy(msg->data.begin(), msg->data.end(), singleimage_data);
  lcm_img.data.assign(singleimage_data, singleimage_data + ( n_colors*isize));

  lcm_publish_.publish(channel.c_str(), &lcm_img);
  /*
  namespace enc = sensor_msgs::image_encodings;
  cv_bridge::CvImageConstPtr left_ptr;
  cv_bridge::CvImageConstPtr right_ptr;
  int isize = l_image->width*l_image->height;

  //cout << l_image->width << " w | h " << l_image->height << "\n";

  bot_core::image_t stereo;
  stereo.utime =current_utime;
  stereo.width =l_image->width;
  stereo.height =2*l_image->height;
  stereo.nmetadata =0;

  if (l_image->encoding.compare("bgr8") == 0){
    // Need to convert image to OpenCV to invert R and B:
    // OpenCV: BGR | LCM: RGB
    int n_colors = 3; // 1 is grey, 3 is rgb
    left_ptr =  cv_bridge::toCvShare(l_image, enc::BGR8);//MONO8);
    right_ptr =  cv_bridge::toCvShare(r_image, enc::BGR8);//MONO8);
    cv::Mat l_img;
    cvtColor( left_ptr->image, l_img, CV_BGR2RGB);
    cv::Mat r_img;
    cvtColor( right_ptr->image, r_img, CV_BGR2RGB);

    // Write to file:
    //cv::imwrite("left.png", left_ptr->image);
    //cv::imwrite("right.png", right_ptr->image);

    stereo.row_stride=n_colors*l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_RGB;
    stereo.size =n_colors *2*isize;
    copy(l_img.data, l_img.data + n_colors*isize, stereo_data);
    copy(r_img.data, r_img.data + n_colors*isize, stereo_data  + (n_colors * isize));
    stereo.data.assign(stereo_data, stereo_data + ( n_colors*2*isize));
  }else if (l_image->encoding.compare("mono8") == 0){
    stereo.row_stride=l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_GRAY;
    stereo.size =2*isize;
    copy(l_image->data.begin(), l_image->data.end(), stereo_data);
    copy(r_image->data.begin(), r_image->data.end(), stereo_data + (l_image->width*l_image->height));
    stereo.data.assign(stereo_data, stereo_data + ( 2*isize));
  }else if (l_image->encoding.compare("bayer_bggr8") == 0){
    stereo.row_stride=l_image->width;
    stereo.pixelformat =bot_core::image_t::PIXEL_FORMAT_BAYER_BGGR;
    stereo.size =2*isize; // I think its the same size as a typical grayscale...
    copy(l_image->data.begin(), l_image->data.end(), stereo_data);
    copy(r_image->data.begin(), r_image->data.end(), stereo_data + (l_image->width*l_image->height));
    stereo.data.assign(stereo_data, stereo_data + ( 2*isize));
  }else{
    cout << l_image->encoding << " image encoded not supported, not publishing\n";
    cout << stereo_out_ << "\n";
    return;
  }


  */



/*  image_data = new uint8_t [640*480*3];
  IplImage *imageBGR = cvCreateImage(cvSize( msg->width ,   msg->height), 8, 3);
  IplImage* imageRGB = cvCreateImage(cvSize( msg->width ,   msg->height), 8, 3);

  copy(msg->data.begin(), msg->data.end(), image_data);
  imageBGR->imageData = (char*) image_data;
  cvCvtColor( imageBGR, imageRGB, CV_BGR2RGB );
  Mat imageRGBmat(imageRGB);

  bot_core_image_t img;
  img.utime = (int64_t) floor(msg->header.stamp.toNSec()/1000);
  img.width = msg->width;
  img.height =msg->height;
  img.row_stride = 3*msg->width; // check this
  img.size = msg->width*msg->height*3;
  img.nmetadata=0;
  img.metadata=NULL;
  img.data=imageRGBmat.data;
  img.pixelformat =BOT_CORE_IMAGE_T_PIXEL_FORMAT_RGB;
  bot_core_image_t_publish(lcm_publish_,channel.c_str(), &img);

  if (VERBOSE){
    cout << "got: " << channel<< "\n";
    cout << msg->width << ", " << msg->height << ", "
        << msg->encoding << ", " << ((int) msg->is_bigendian) << ", " << msg->step << "\n";
    //640, 480, mono8, 0, 640
    cout << img.utime << "\n";
  }
  cvReleaseImage(&imageBGR);
  cvReleaseImage(&imageRGB);
  delete[] image_data;*/
}


void App::rstate_cb(const atlas_gazebo_msgs::RobotStateConstPtr& msg){
  drc::robot_state_t robot_state_msg;
  robot_state_msg.utime = (int64_t) msg->header.stamp.toNSec()/1000; // from nsec to usec
  robot_state_msg.robot_name = msg->robot_name;
  robot_state_msg.origin_position.translation.x = msg->body_pose.position.x;
  robot_state_msg.origin_position.translation.y = msg->body_pose.position.y;
  robot_state_msg.origin_position.translation.z = msg->body_pose.position.z;
  robot_state_msg.origin_position.rotation.x = msg->body_pose.orientation.x;
  robot_state_msg.origin_position.rotation.y = msg->body_pose.orientation.y;
  robot_state_msg.origin_position.rotation.z = msg->body_pose.orientation.z;
  robot_state_msg.origin_position.rotation.w = msg->body_pose.orientation.w;

  robot_state_msg.origin_twist.linear_velocity.x =msg->body_twist.linear.x;
  robot_state_msg.origin_twist.linear_velocity.y =msg->body_twist.linear.y;
  robot_state_msg.origin_twist.linear_velocity.z =msg->body_twist.linear.z;
  robot_state_msg.origin_twist.angular_velocity.x =msg->body_twist.angular.x;
  robot_state_msg.origin_twist.angular_velocity.y =msg->body_twist.angular.y;
  robot_state_msg.origin_twist.angular_velocity.z =msg->body_twist.angular.z;

  int i,j;
  for(i = 0; i < 6; i++)  {
    for(j = 0; j < 6; j++) {
      robot_state_msg.origin_cov.position_cov[i][j] = 0;
      robot_state_msg.origin_cov.twist_cov[i][j] = 0;
    }
  }

  robot_state_msg.num_joints = msg->joint_name.size();
  robot_state_msg.joint_name = msg->joint_name;

  drc::joint_covariance_t j_cov;
  j_cov.variance = 0;

  for (std::vector<int>::size_type i = 0; i != robot_state_msg.joint_name.size(); i++)  {
    robot_state_msg.joint_position.push_back(msg->joint_position[i]);
    robot_state_msg.joint_velocity.push_back(msg->joint_velocity[i]);
    robot_state_msg.measured_effort.push_back(0);
    robot_state_msg.joint_cov.push_back(j_cov);
  }

  // dummy ground contact states
  robot_state_msg.contacts.num_contacts =8;
  robot_state_msg.contacts.id.push_back("LFootToeIn");
  robot_state_msg.contacts.id.push_back("LFootToeOut");
  robot_state_msg.contacts.id.push_back("LFootHeelIn");
  robot_state_msg.contacts.id.push_back("LFootHeelOut");
  robot_state_msg.contacts.id.push_back("RFootToeIn");
  robot_state_msg.contacts.id.push_back("RFootToeOut");
  robot_state_msg.contacts.id.push_back("RFootHeelIn");
  robot_state_msg.contacts.id.push_back("RFootHeelOut");
  for (int i=0; i< robot_state_msg.contacts.num_contacts; i++){
    robot_state_msg.contacts.inContact.push_back(0);
    drc::vector_3d_t f_zero;
    f_zero.x = 0;f_zero.y = 0;f_zero.z = 0;
    robot_state_msg.contacts.contactForce.push_back(f_zero);
  }

  lcm_publish_.publish("TRUE_ROBOT_STATE", &robot_state_msg);
}


int scan_counter=0;
void App::rotating_scan_cb(const sensor_msgs::LaserScanConstPtr& msg){
  scan_counter++;
  if (scan_counter%80 ==0){
    std::cout << scan_counter << " /multisense_sl/laser/scan -> ROTATING_SCAN\n";
  }  
  send_lidar(msg, "ROTATING_SCAN");
}
void App::scan_left_cb(const sensor_msgs::LaserScanConstPtr& msg){
  send_lidar(msg, "SCAN_LEFT");
}
void App::scan_right_cb(const sensor_msgs::LaserScanConstPtr& msg){
  send_lidar(msg, "SCAN_RIGHT");
}


void App::send_lidar(const sensor_msgs::LaserScanConstPtr& msg,string channel ){
  bot_core::planar_lidar_t scan_out;
  for (size_t i=0; i < msg->ranges.size(); i++){
    scan_out.ranges.push_back( msg->ranges[i] );
  }
  scan_out.utime = (int64_t) floor(msg->header.stamp.toNSec()/1000);
  scan_out.nranges =msg->ranges.size();
  // TODO: pass the intensities:
  scan_out.nintensities=0;
  //scan_out.intensities=NULL;
  scan_out.rad0 = msg->angle_min;
  scan_out.radstep = msg->angle_increment;

  lcm_publish_.publish(channel.c_str(), &scan_out);
  if (VERBOSE) cout << channel << ": "<< scan_out.utime << "\n";
}


int main(int argc, char **argv){
  ros::init(argc, argv, "ros2lcm");
  ros::CallbackQueue local_callback_queue;
  ros::NodeHandle nh;
  nh.setCallbackQueue(&local_callback_queue);
  

  App *app = new App( "multisense_sl/camera", "CAMERA", nh);
  std::cout << "ros2lcm translator ready\n";
  //ros::spin();
  
  
  
  while (ros::ok()){
    local_callback_queue.callAvailable(ros::WallDuration(0.01));
  }
  
  return 0;
}