extends KinematicBody2D

const GRAVITY = 0.17
const coin = preload("res://actors/items/coin/coin_yellow.tscn")
const sfx = {
	"jump": preload("res://audio/sfx/items/goomba/goomba_jump.ogg"),
	"step": preload("res://audio/sfx/items/goomba/goomba_step.wav"),
	#"squish": preload("res://audio/sfx/items/goomba/goomba_jump.ogg"),
	}

var vel = Vector2.ZERO

export var direction = 1

var is_jumping = false #this is for stopping goomba's movement and then
#transition to higher speed.

var target = null
var wander_dist = 0
var stepped = false
var full_jump = false
var dead = false
var struck = false
var land_timer = 0
var collect_id
var water_bodies : int = 0

onready var hurtbox = $Hurtbox
onready var sprite = $AnimatedSprite
onready var raycast = $RayCast2D
onready var sfx_active = $SFXActive
onready var sfx_passive = $SFXPassive
onready var main = $"/root/Main"

func _ready():
	collect_id = Singleton.get_collect_id()
	sprite.frame = hash(position.x + position.y * PI) % 4
	sprite.playing = true


func _physics_process(_delta):
	if target != null && target.locked:
		target = null
	if sprite.animation == "squish":
		if dead:
			if Singleton.request_coin(collect_id):
				var spawn = coin.instance()
				spawn.position = position
				spawn.dropped = true
				main.add_child(spawn)
			queue_free()
		else:
			if !struck:
				if target.position.y + 16 > global_position.y - 10:
					target.vel.y = 0
					target.position.y += 0.5
				if Input.is_action_just_pressed("jump"):
					full_jump = true
			
			if sprite.frame == 3:
				if !struck:
					if target.state == target.s.edive:
						target.coyote_time = 0
						target.dive_correct(-1)
						target.switch_state(target.s.diveflip)
						target.switch_anim("jump")
						target.flip_l = target.sprite.flip_h
						target.vel.y = min(-target.set_jump_1_vel/1.5, target.vel.y)
						target.double_jump_state = 0
					else:
						if Input.is_action_pressed("jump"):
							if full_jump:
								target.vel.y = -6.5
							else:
								target.vel.y = -6
						else:
							target.vel.y = -5
						target.switch_state(target.s.walk)
				dead = true #apparently queue_free() doesn't cancel the current cycle
			
	#code to push enemies apart - maybe come back to later?
#	for area in get_overlapping_areas():
#		if area != target:
#			if global_position.x > area.global_position.x || (global_position.x == area.global_position.x && id > area.id):
#				get_parent().vel.x += 7.5
#			else:
#				get_parent().vel.x -= 7.5

	if !is_on_floor() && sprite.animation != "squish":
		sprite.frame = 1
		raycast.enabled = false
	
	if water_bodies > 0:
		vel.y = min(vel.y + GRAVITY, 2)
	else:
		vel.y = min(vel.y + GRAVITY, 6)
	
	if sprite.animation != "squish" && !struck:
		#raycast2d is used here to detect if the object collided with a wall
		#to change directions
		if direction == 1:
			sprite.flip_h = true
		elif direction == -1:
			sprite.flip_h = false
		
		if is_on_floor():
			if is_on_wall() && target == null:
				vel.x = 0
				flip_ev()
				wander_dist = 0
			
			if !raycast.is_colliding() && raycast.enabled:
				flip_ev()
				
			if sprite.animation == "jumping":
				if is_jumping:
					sprite.frame = 2
					land_timer = 0
					is_jumping = false
					raycast.enabled = true
				
				land_timer += 0.2
				if land_timer >= 1.8:
					sprite.frame = 0
					sprite.animation = "walking"
				else:
					sprite.frame = 2 + land_timer #finish up jumping anim
			else:
				vel.y = GRAVITY
				if sprite.frame == 0 || sprite.frame == 3:
					if !stepped:
						sfx_passive.pitch_scale = rand_range(0.9, 1.1)
						sfx_passive.play()
						stepped = true
				else:
					stepped = false
				if target != null:
					sprite.speed_scale = abs(vel.x) / 2 + 1
					if target.position.x - position.x < -20 || (target.position.x < position.x && abs(target.position.y - position.y) < 26):
						vel.x = max(vel.x - 0.1, -2)
						direction = -1
						raycast.position.x = -9
						sprite.playing = true
					elif target.position.x - position.x > 20 || (target.position.x > position.x && abs(target.position.y - position.y) < 26):
						vel.x = min(vel.x + 0.1, 2)
						direction = 1
						raycast.position.x = 9
						sprite.playing = true
					else:
						vel.x *= 0.85
						if sprite.frame == 0:
							sprite.playing = false
				else:
					sprite.speed_scale = 1
					sprite.playing = true
					if direction == 1:
						vel.x = min(vel.x + 0.1, 1)
					else:
						vel.x = max(vel.x - 0.1, -1)
					wander_dist += 1
					if wander_dist >= 120 && sprite.frame == 0:
						wander_dist = 0
						direction *= -1
		else:
			sprite.animation = "jumping"
			if !is_jumping:
				sprite.frame = 1
		var bodies = hurtbox.get_overlapping_bodies()
		if bodies.size() > 0:
			damage_check(bodies[0])
				
	var snap
	if !is_on_floor() || sprite.animation == "jumping":
		snap = Vector2.ZERO
	else:
		snap = Vector2(0, 4)
	#warning-ignore:RETURN_VALUE_DISCARDED
	move_and_slide_with_snap(vel * 60, snap, Vector2.UP, true)
	if is_on_floor() && struck && sprite.animation != "squish":
		sprite.animation = "squish"
		sprite.frame = 0
		sprite.playing = true
		
#the next signals are used for the aggresive trigger
#behaviour, it changes the vel and goes towards
#the target, it also changes the raycast2d because
#after mario goes away, the enemy returns to its
#pacific state

#they also use the same trick as the directional collision
#for hurting mario or the enemy itself, but less complicated
#as we need only the x coordinates

func _on_Collision_mario_detected(body):
	if target == null && sprite.animation != "squish" && !body.locked:
		if body.position.x > position.x:
			direction = 1
		else:
			direction = -1
		target = body
		if is_on_floor():
			sprite.animation = "jumping"
			sfx_active.stream = sfx["jump"]
			sfx_active.play()
			sprite.frame = 0
			is_jumping = true
			vel.y = -2.5
		wander_dist = 0


func flip_ev():
	direction *= -1
	raycast.position.x *= -1


func _on_AwareArea_body_exited(_body):
	target = null
	

func _on_Area2D_body_entered_hurt(body):
	if sprite.animation != "squish":
		if body.hitbox.global_position.y + body.hitbox.shape.extents.y - body.vel.y - 6 < position.y && body.vel.y > 0:
			sprite.animation = "squish"
			struck = false
			vel.y = 0
			sprite.frame = 0
			sprite.playing = true
			if target.state == target.s.dive || target.state == target.s.edive:
				if Input.is_action_pressed("down"):
					damage_check(body)
				else:
					target.call_deferred("switch_state", target.s.edive)
			else:
				target.call_deferred("switch_state", target.s.ejump)
		elif !struck:
			damage_check(body)


func damage_check(body):
	if body.is_spinning() || (body.is_diving(true) && abs(body.vel.x) > 1) || body.state == body.s.ejump:
		struck = true
		vel.y -= 2.63
		sprite.animation = "jumping"
		vel.x = max((12 + abs(vel.x) / 1.5), 0) * 5.4 * sign(position.x - body.position.x) / 10 / 1.5
	else:
		body.take_damage_shove(1, sign(body.position.x - position.x))


func _on_WaterCheck_area_entered(_area):
	water_bodies += 1


func _on_WaterCheck_area_exited(_area):
	water_bodies -= 1
