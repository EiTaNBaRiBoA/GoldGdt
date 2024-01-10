#	Copyright (c) 2024 ratmarrow
#	
#	Permission is hereby granted, free of charge, to any person obtaining a copy
#	of this software and associated documentation files (the "Software"), to deal
#	in the Software without restriction, including without limitation the rights
#	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#	copies of the Software, and to permit persons to whom the Software is
#	furnished to do so, subject to the following conditions:
#	
#	The above copyright notice and this permission notice shall be included in all
#	copies or substantial portions of the Software.
#	
#	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#	SOFTWARE.
#	
#	-------------------------------------------------------------------------------------------------
#	
#	"GoldGdt" is designed to accurately port the 'pm_shared.c' movement code from Valve's GoldSrc engine to Godot 4.2.
#	This repository comes pre-bundled with a smoothing plugin provided by Lawnjelly (https://github.com/lawnjelly/smoothing-addon)
#	Thank you for using GoldGdt, and happy developing!
#	
#	- ratmarrow <3

extends CharacterBody3D

#region Variables
# A "Hammer Unit" (Quake, GoldSrc, etc.) is 1 inch.
# multiply Godot units (meters) by this to get the Hammer unit conversion,
# divide Hammer units by this to get the Godot unit conversion.
const HAMMERUNIT = 39.37 

# Debug

@onready var start_pos : Vector3 = position

# Player Input
# In GoldSrc, the individual movement input directions have a speed to them, this allows you to modify player speed on a per-axis basis.
# UP_SPEED has been overlooked in this project because it ties to unimplemented swimming and ladders, which haven't yet been added.

var FORWARD_SPEED = 8.128 # Forward and backward move speed, measured in meters (320 HU)
var SIDE_SPEED = 8.128 # Left and right move speed, measured in meters (320 HU)

var input_vector : Vector2 = Vector2.ZERO
var move_dir : Vector3 = Vector3.ZERO
var jump_on : bool = false

# Player Movement

const WALKACCEL = 10.0 # Ground acceleration multiplier, engine agnostic
const MAXAIRSPEED = 0.762 # The maximum speed you can accelerate to in the _airaccelerate() function, measured in meters (30 HU)
const AIRACCEL = 10.0 # Air acceleration multiplier, engine agnostic
const FRICTION = 4.0 # Friction multiplier, engine agnostic
const STOPSPEED = 2.54 # Speed threshold for stopping in the _friction() function, measured in meters (100 HU)
const GRAVITY = 20.32 # Speed of gravity, measured in meters (800 HU)
const JUMPHEIGHT = 1.143 # Height of the player's jump, measured in meters (45 HU)
const DUCKINGSPEEDMULTIPLIER = 0.333; # Value to multiply move_dir by when crouching, engine agnostic

var FRICTION_STRENGTH = 1.0 # How much the overall friction calculation applies to your velocity. Not constant to allow for surface-based changes.

# Player State

var ducking : bool = false
@export var crouchtraces : Array[RayCast3D] # List of Raycasts that check upwards to see if uncrouching will clip you into a ceiling.

# Player Dimensions
# Currently, the player uses a capsule collision hull, which isn't accurate to GoldSrc. This was because I ran into issues with slop movement
# using a Box Shape, but I am keeping the code like this in the even either someone can make Box Shape work, or if it's just a bug with Godot Physics.

const BBOX_STANDING_BOUNDS = Vector3(0.813, 1.829, 0.813) # 32 HU x 72 HU x 32 HU
const BBOX_DUCKING_BOUNDS = Vector3(0.813, 0.914, 0.813) # 32 HU x 36 HU x 32 HU
const VIEW_OFFSET = 0.711 # How much the camera hovers from player origin while standing, measured in meters (28 HU)
const DUCK_VIEW_OFFSET = 0.305 # How much the camera hovers from player origin while crouching, measured in meters(12 HU)

var BBOX_STANDING = CapsuleShape3D.new() 
var BBOX_DUCKING = CapsuleShape3D.new() 

@export var player_hull : CollisionShape3D

# Player Camera

const SENSITIVITY = 0.002
var look_pitch : float
var look_yaw : float

# FIXME: This can be handled leagues better than I handled it.
@export var head : Node3D # Used for rotating the input_vector to where you are facing
@export var vision : Node3D # Used for looking up and down in order to avoid any contamination in the input process
@export var camera : Node3D # Used for the _calc_roll() function to avoid any contamination in the input process

# UI

@export var speedometer : Label
@export var info : Label

# Configuration

## Allows holding down the "pm_jump" input to jump the moment you hit the ground
var autohop : bool = false 
#endregion

# Using _ready() to initialize variables
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# Set bounding box dimensions.
	BBOX_STANDING.height = BBOX_STANDING_BOUNDS.y
	BBOX_STANDING.radius = 0.407
	BBOX_DUCKING.height = BBOX_DUCKING_BOUNDS.y
	BBOX_DUCKING.radius = 0.407
	
	# Set hull and head position to default.
	player_hull.shape = BBOX_STANDING
	head.position.y = VIEW_OFFSET

# Using _input() to handle collecting mouse input
func _input(event):
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look_yaw += -event.relative.x * SENSITIVITY
			look_pitch += -event.relative.y * SENSITIVITY

# Using _process() to handle camera look logic
func _process(delta):
	# Camera logic
	look_pitch = clamp(look_pitch, deg_to_rad(-89), deg_to_rad(89))
	head.rotation = head.rotation.slerp(Vector3(0, look_yaw, 0), clamp(delta * 98, 0.01, 0.98))
	vision.rotation = vision.rotation.slerp(Vector3(look_pitch, 0, 0), clamp(delta * 98, 0.01, 0.98))
	camera.rotation = camera.rotation.slerp(Vector3(0, 0, _calc_roll(1, 300)), clamp(delta * 98, 0.01, 0.98))
	
	#region Character Info UI, remove if deemed necessary
	var speed_format = "%s in/s (goldsrc)\n%s m/s (godot)"
	var speed_string = speed_format % [str(roundi((Vector3(velocity.x * HAMMERUNIT, 0.0, velocity.z * HAMMERUNIT).length()))), str(roundi((Vector3(velocity.x, 0.0, velocity.z).length())))]
	speedometer.text = speed_string
	
	var info_format = "frametime: %s\npos (meters): %s\nvel (meters): %s\ngrounded: %s\ncrouching: %s"
	var info_string = info_format % [str(get_physics_process_delta_time()), str(position), str(velocity), str(is_on_floor()), str(ducking)]
	info.text = info_string
	#endregion
	
	# Toggle mouse mode while debugging, remove and replace with your own official setup
	if Input.is_action_just_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE else Input.MOUSE_MODE_VISIBLE

# Using _physics_process() for handling movement *and* input in order to make player physics as reliable as possible.
# GoldSrc games like Half-Life operated on the framerate the game was running at, which would make physics inconsistent.
# You can change the physics update rate in the Project Settings, but I built this system around running at 100 FPS.
func _physics_process(delta):
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# FIXME: Debug code that teleports you to start_pos in case you fall out of map.
	# Remove this condition and the action "debug_respawn" as you see fit.
	if Input.is_action_just_pressed("debug_respawn"):
		position = start_pos
	
	_handle_input()
	_handle_movement(delta)
	_handle_collision()

# Intercepts the move_and_slide() function to add slope sliding, recreating surfing.
func _handle_collision() -> void:
	var collided := move_and_slide()
	if collided and not get_floor_normal():
		var slide_direction := get_last_slide_collision().get_normal()
		velocity = velocity.slide(slide_direction)

# Gathers player input for use in movement calculations
func _handle_input() -> void:
	var ix = Input.get_action_raw_strength("pm_moveright") - Input.get_action_raw_strength("pm_moveleft")
	var iy = Input.get_action_raw_strength("pm_movebackward") - Input.get_action_raw_strength("pm_moveforward")
	input_vector = Vector2(ix, iy).normalized()
	move_dir = head.transform.basis * Vector3(input_vector.x * FORWARD_SPEED, 0, input_vector.y * SIDE_SPEED)
	
	jump_on = Input.is_action_pressed("pm_jump") if autohop else Input.is_action_just_pressed("pm_jump")
	pass

# Handles movement and jumping physics
func _handle_movement(delta: float) -> void:
	_duck()
	
	# Check if we are on ground
	if is_on_floor():
		if jump_on:
			_do_jump(delta) # Not running friction on ground if you press jump fast enough allows you to preserve all speed
		else: # Otherwise do normal floor movement
			_friction(delta, FRICTION_STRENGTH)
			_accelerate(delta, move_dir.normalized(), move_dir.length(), WALKACCEL)
	else: 
		_airaccelerate(delta, move_dir.normalized(), move_dir.length(), AIRACCEL)

# Adds to the player's velocity based on direction, speed and acceleration.
func _accelerate(delta: float, wishdir: Vector3, wishspeed: float, accel: float):
	var addspeed : float
	var accelspeed : float
	var currentspeed : float
	
	# See if we are changing direction a bit
	currentspeed = velocity.dot(wishdir)
	
	# Reduce wishspeed by the amount of veer.
	addspeed = wishspeed - currentspeed
	
	# If not going to add any speed, done.
	if addspeed <= 0:
		return;
		
	# Determine the amount of acceleration.
	accelspeed = accel * wishspeed * delta
	
	# Cap at addspeed
	if accelspeed > addspeed:
		accelspeed = addspeed
	
	# Adjust velocity.
	velocity += accelspeed * wishdir

# Adds to the player's velocity based on direction, speed and acceleration. 
# The difference between _accelerate() and this function is it caps the maximum speed you can accelerate to.
func _airaccelerate(delta: float, wishdir: Vector3, wishspeed: float, accel: float):
	var addspeed : float
	var accelspeed : float
	var currentspeed : float
	var wishspd : float = wishspeed
	
	if (wishspd > MAXAIRSPEED):
		wishspd = MAXAIRSPEED
	
	# See if we are changing direction a bit
	currentspeed = velocity.dot(wishdir)
	
	# Reduce wishspeed by the amount of veer.
	addspeed = wishspd - currentspeed
	
	# If not going to add any speed, done.
	if addspeed <= 0:
		return;
		
	# Determine the amount of acceleration.
	accelspeed = accel * wishspeed * delta
	
	# Cap at addspeed
	if accelspeed > addspeed:
		accelspeed = addspeed
	
	# Adjust velocity.
	velocity += accelspeed * wishdir

# Applies friction to the player's horizontal velocity
func _friction(delta: float, strength: float):
	var speed = velocity.length()
	
	# Bleed off some speed, but if we have less that the bleed
	# threshold, bleed the threshold amount.
	var control = STOPSPEED if (speed < STOPSPEED) else speed
	
	# Add the amount to the drop amount
	var drop = control * delta * FRICTION * strength
	
	# Scale the velocity.
	var newspeed = speed - drop
	
	if newspeed < 0:
		newspeed = 0
	
	if speed > 0:
		newspeed /= speed
	
	velocity.x *= newspeed
	velocity.z *= newspeed

# Applies a jump force to the player.
func _do_jump(delta: float) -> void:
	# Apply the jump impulse
	velocity.y = sqrt(2 * GRAVITY * 1.143)
	
	# Add in some gravity correction
	velocity.y -= (GRAVITY * delta * 0.5 )

# Handles crouching logic.
# TODO: In GoldSrc, there is a 0.4 second window where the collision hull is unchanged, called the "ducking window."
# This creates a piece of movement tech called "ducktapping" which acts as a minijump. This isn't present in this implementation,
# but I plan to implement it at a later date.
func _duck() -> void:
	# If we aren't ducking, but are holding the "pm_duck" input...
	if ducking == false and Input.is_action_pressed("pm_duck"):
		# Move our character down in order to stop them from "falling" after crouching, but ONLY on the ground.
		if is_on_floor():
			position.y -= 0.457
		
		# Set the collision hull and view offset to the ducking counterpart.
		player_hull.shape = BBOX_DUCKING
		head.position.y = DUCK_VIEW_OFFSET
		ducking = true
	
	# Check for if we are ducking and if we are no longer holding the "pm_duck" input...
	if ducking and !Input.is_action_pressed("pm_duck"):
		# ... And try to get back up to standing height.
		_unduck()
	
	# Bring down the move direction to a third of it's speed.
	if ducking:
		move_dir *= DUCKINGSPEEDMULTIPLIER

# Checks to make sure uncrouching won't clip us into a ceiling.
func _unduck():
	if _check_traces():
		ducking = true
		return
	else:
		ducking = false
		player_hull.shape = BBOX_STANDING
		head.position.y = VIEW_OFFSET
		if is_on_floor(): position.y += 0.457

# Returns true if any of the Raycasts in the "crouchtraces" array are colliding.
func _check_traces() -> bool:
	for t in crouchtraces:
		if t.is_colliding(): return true
	
	return false

# Returns a value for how much the camera should tilt to the side.
func _calc_roll(rollangle: float, rollspeed: float) -> float:
	
	var side = velocity.dot(head.transform.basis.x)
	
	var roll_sign = 1.0 if side < 0.0 else -1.0
	
	side = absf(side)
	
	var value = rollangle
	
	if (side < rollspeed):
		side = side * value / rollspeed
	else:
		side = value
	
	return side * roll_sign
