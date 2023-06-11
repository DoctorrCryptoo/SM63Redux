tool
class_name TerrainBorder
extends Node2D
# Handles drawing of terrain polygons' border graphics, except for
# the endcaps of top edges.
#
# Border graphics are always ordered with top edges (and endcaps) in front,
# then bottom edges, then sides.

enum EdgeType {
	NONE,
	TOP,
	BOTTOM,
	SIDE,
}

const QUAD_RADIUS = 16

onready var root = $".."
onready var body_polygon: Polygon2D = $"../Body"
onready var top_edges: TerrainBorderEndcaps = $"../TopEdges"


func _draw():
	# Clear polygons created last time we updated.
	for child in get_children():
		remove_child(child)
	
	# Load appearance from the root.
	body_polygon.texture = root.body
	body_polygon.polygon = root.polygon
	body_polygon.color = root.tint_color if root.tint else Color(1, 1, 1)
	
	# Clear the draw queue for top edges
	top_edges.area_queue = []
	# Draw all terrain polygons.
	add_full(root.polygon)
	# Queue drawing the top edges.
	top_edges.update()


func generate_polygons_top(lines, z_order = 2):
	# First create quads from each line segment.
	var quads = []
	var p_len = lines.size()
	for ind in range(p_len):
		quads.append(_generate_quad(lines, ind))
	
	# Convert the quads into drawable areas with extra data.
	# This is necessary for endcap generation.
	var areas = []
	for ind in range(p_len - 1):
		var cur_group = quads[ind]
		var next_group = quads[(ind + 1) % p_len]
		
		# Save information needed for drawing.
		areas.append({
			index = ind,
			verts = cur_group,
			direction = cur_group[0].direction_to(cur_group[1]),
			normal = cur_group[0].direction_to(cur_group[1]).tangent(),
			clock_dir = 1,
			type = "quad"
		})
		
		# If this is the last entry in the group, early exit.
		if ind == p_len - 2:
			break
		
		# Didn't early exit. Time to resolve intersections between groups.
		
		# Does the top of this area intersect the top of the next?
		var top_intersect = Geometry.segment_intersects_segment_2d(
			cur_group[0], cur_group[1],
			next_group[0], next_group[1]
		)
		if top_intersect:
			# Set the colliding segments to meet at the same point.
			var cur_ind = 1
			var next_ind = 0
			cur_group[cur_ind] = top_intersect
			next_group[next_ind] = top_intersect
			
			# Add an area between these.
			var opp_cur_ind = 2
			var opp_next_ind = 3
			_add_inbetween_segment(
				areas,
				cur_group[opp_cur_ind],
				next_group[opp_next_ind],
				top_intersect
			)
		
		# Does the bottom of this area intersect the bottom of the next?
		var bottom_intersect = Geometry.segment_intersects_segment_2d(
			cur_group[2], cur_group[3],
			next_group[2], next_group[3]
		)
		if bottom_intersect:
			# TODO: Same code as above, different segment indices.
			# Set the colliding segments to meet at the same point.
			var cur_ind = 2
			var next_ind = 3
			cur_group[cur_ind] = bottom_intersect
			next_group[next_ind] = bottom_intersect
			
			# Add an area between these.
			var opp_cur_ind = 1
			var opp_next_ind = 0
			_add_inbetween_segment(
				areas,
				cur_group[opp_cur_ind],
				next_group[opp_next_ind],
				bottom_intersect
			)
	
	# Draw everything
	# Mark the left-side area for drawing.
	top_edges.area_queue.append([true, areas.front()])
	
	# Draw all areas.
	for area in areas:
		# Turn this area into a polygon node.
		var poly2d = _create_polygon(area.verts, area.normal, z_order, root.top,
			0 if area.type == "quad" or (area.clock_dir == -1 and area.type == "trio") 
			else area.verts.size() - 2)
		
		# Add it as a child.
		add_child(poly2d)
		
		# Make a duplicate polygon to hold the shadow texture.
		# TODO: This may be meant to get clipped to within the polygon's body.
		if !root.tint:
			var shade = poly2d.duplicate()
			shade.texture = root.top_shade
			add_child(shade)
	
	# Mark the right-side area for drawing.
	top_edges.area_queue.append([false, areas.back()])


func _add_inbetween_segment(areas, start: Vector2, end: Vector2, circumcenter: Vector2):
	# A "circumcenter," for clarity, is when you draw a circle that touches all
	# points of a polygon, then take the center of that circle.
	
	# Initialize verts array with starting point.
	var verts = [start]
	
	# Find angle of the (circumcenter -> start) vector relative to the X axis.
	var s_unit = circumcenter.direction_to(start)
	var s_angle = atan2(s_unit.y, s_unit.x)
	# Likewise for (circumcenter -> end).
	var e_unit = circumcenter.direction_to(end)
	var e_angle = atan2(e_unit.y, e_unit.x)
	
	# Find angle between start and end.
	# (Currently, only the sign of this is used, so the division isn't needed.)
	var delta = (e_angle - s_angle) / 5.0
	
	# Circular edges, this doesn't work rn, I'll work on it later
	
#    #for if e_angle > s_angle
#    while angle < e_angle:
#        angle += delta
#        var vert = circumcenter + Vector2(cos(angle), sin(angle)) * distance
#        verts.append(vert)
#    #for if e_angle < s_angle
#    angle = s_angle
#    while angle > e_angle:
#        angle += delta
#        var vert = circumcenter + Vector2(cos(angle), sin(angle)) * distance
#        verts.append(vert)
	
	# Add the endpoint.
	verts.append(end)
	# Add the circumcenter (to make a triangle?).
	verts.append(circumcenter)
	
	# Add the triangle we just created to the areas.
	areas.append({
		verts = verts,
		normal = start.direction_to(end).rotated(-PI / 2),
		clock_dir = sign(delta),
		type = "trio"
	})


func generate_polygons(lines: Array, texture: Texture, z_index: int):
	var p_len = lines.size()
	for ind in range(p_len - 1):
		# First create quads from each line segment.
		var verts = _generate_quad(lines, ind)
		
		# Find the normal of this line segment too.
		# TODO: This is also done in _generate_quad. If this loop ever needs
		# optimizing, here's some work to deduplicate.
		var normal := _normal_of_segment(lines[ind], lines[(ind + 1) % p_len])
		
		# Create a child polygon node.
		add_child(_create_polygon(verts, normal, z_index, texture, 0))


func _generate_quad(chain: Array, start_idx: int, thickness: int = QUAD_RADIUS):
	# Find the normal of this line segment.
	var current: Vector2 = chain[start_idx]
	var next: Vector2 = chain[(start_idx + 1) % chain.size()]
	var normal := _normal_of_segment(current, next)
	
	# The direction to move verts in order to thicken the line.
	var thicken_vec := normal * thickness
	
	# From the line segment, generate a quad with thickness.
	# The quad's vertices run clockwise around its perimeter.
	return [
		# Top edge
		current + thicken_vec,
		next + thicken_vec,
		# Bottom edge
		next - thicken_vec,
		current - thicken_vec
	]


func _create_polygon(
	verts: Array, normal: Vector2,
	z_order: int,
	texture: Texture, origin_idx: int
) -> Polygon2D:
	# Create a polygon node from the terrain's data....
	var poly2d = Polygon2D.new()
	poly2d.texture = texture
	poly2d.color = root.tint_color if root.tint else Color(1, 1, 1)
	# ...and the area's data.
	poly2d.polygon = verts
	# This one will be important later.
	poly2d.texture_rotation = -normal.angle() - PI / 2

	# Variables needed to set texture offset.
	# Rotated versions of the X and Y axes.
	var unit = Vector2(sin(poly2d.texture_rotation), cos(poly2d.texture_rotation))
	# Position of the area's origin (chosen from one of the verts).
	var pos = verts[origin_idx]
	# Texture offset. This is never set, so this may not be needed?
	var tex_offset = Vector2(0, 0)
	
	# Scale the texture, not sure if this is still needed, it appears not so it is commented for now
	#if area.type == "trio":
	#	var dist = area.verts[0].distance_to(area.verts.back())
	#	poly2d.texture_scale.y = 16 / dist

	# Calculate rotated texture offset (relative to the chosen origin?).
	poly2d.texture_offset.x = -unit.y * pos.x + unit.x * pos.y - tex_offset.x
	poly2d.texture_offset.y = -unit.x * pos.x - unit.y * pos.y - tex_offset.y
	
	# Set polygon's Z index.
	poly2d.z_index = z_order
	
	# Polygon is ready now; add it to the scene.
	return poly2d


# Beginning from a given point in a polygon, find a chain of line segments that
# share a type ID, OR that should have that ID based on the segments' angles.
# Appends the verts in the chain into the end of `lines`, then returns the index
# of the tail-end vertex.
func get_connected_lines_directional(
	lines: Array, # Output array of polygon points.
	overrides: Dictionary, # Dict of segements' assigned type IDs.
	direction: Vector2, # Direction angle is checked against.
	poly: PoolVector2Array, # Points in the polygon.
	start: int, # Vertex we start/resume the search on.
	type_id: int # ID of the edge type we're searching for.
):
	# The core idea is: iterate the polygon from a given starting point until
	# we find a chain of lines that have the desired type ID.
	# Then, add verts to the output buffer until we reach the end of that chain.
	var p_len = poly.size()
	var added = false
	
	for ind in range(start, p_len):
		# Current vertex.
		var vert: Vector2 = poly[ind]
		# "Up" relative to segment (vert, next).
		var normal: Vector2 = _normal_of_segment(vert, poly[(ind + 1) % p_len])
		# The surface's angle relative to the reference direction.
		var angle: float = normal.angle_to(direction) / PI * 180
		
		if (
			# Has this segment's type been specifically set to the desired type?
			check_override(ind, type_id, overrides)
		) or (
			# If type is not set, is it within the range this type normally is?
			!overrides.has(ind) and check_line_angle(angle)
		):
			# Save this segment's type so we can look it up in the future.
			overrides[ind] = type_id
			# Add the vertex to the output buffer.
			lines.append(vert)
			
			# Remember that we've now started a chain.
			added = true
		elif added:
			# We've reached the end of this chain.
			# Add the tail vert, then return where the chain stops.
			lines.append(vert)
			return ind
		else:
			# No chain has started yet. Keep iterating.
			pass
	
	# The whole polygon has been iterated. Either no more chains have been
	# found, or the chain continues past the final vert.
	return null


# Beginning from a given point in a polygon, find a chain of line segments that
# share a type ID, without checking the segments' angles.
# Appends the verts in the chain into the end of `lines`, then returns the index
# of the tail-end vertex.
func get_connected_lines_overrides(
	lines: Array, # Output array of polygon points.
	override_list: Dictionary, # Dict of segements' assigned type IDs.
	poly: PoolVector2Array, # Points in the polygon.
	start: int, # Vertex we start/resume the search on.
	type_id: int # ID of the edge type we're searching for.
):
	var p_len = poly.size()
	var added = false
	
	for ind in range(start, p_len):
		var vert: Vector2 = poly[ind]
		
		# Is segment (ind, ind+1)'s type set to the passed ID? Or unset?
		if !override_list.has(ind) or override_list[ind] == type_id:
			# Save this vert, then start a chain.
			lines.append(vert)
			added = true
		# If we've started a chain, is the segment's type NOT what we want?
		elif added:
			# Save this vert, then return the final index of the chain.
			lines.append(vert)
			return ind
		# If we haven't started a chain...
		else:
			# ...just fall through to the next vertex.
			pass
	# If we started the chain but never reached an end, the chain ends on vert
	# 0 of the polygon.
	if added:
		lines.append(poly[0])
	
	# The whole polygon has been iterated.
	return null


func _normal_of_segment(vert: Vector2, next: Vector2) -> Vector2:
	# "Up" relative to segment (vert, next).
	return vert.direction_to(next).tangent()


# Check if the type override for the given line index matches with the type id given
func check_override(index: int, type_id: int, override_list: Dictionary) -> bool:
	return override_list.has(index) and override_list[index] == type_id


func check_line_angle(angle: float) -> bool:
	return angle >= -root.max_deviation and angle <= root.max_deviation


func add_full(poly: PoolVector2Array):
	# Dictionary of segments which have had their type ID evaluated.
	# Types are indexed by first vertex: overrides[3] will return the
	# type ID of segment (3, 4).
	var overrides: Dictionary = root.edge_types.duplicate()
	
	# Draw the top edge texture.
	var latest_index = 0
	# Iterate the polygon until all chains of top-edge have been found
	# (including single-segment chains).
	while latest_index != null:
		# Find a single chain of segments with type ID == EdgeType.TOP.
		var list = []
		# Also store the last index in the chain, so we can start from there
		# next iteration of the while loop.
		latest_index = get_connected_lines_directional(list, overrides, root.up_direction, poly, latest_index, EdgeType.TOP)
		
		# Valid chains contain at least 2 vertices.
		# If the chain is valid, draw it.
		if list.size() >= 2:
			generate_polygons_top(list)
	
	# Do the bottom as well--same exact deal.
	latest_index = 0
	while latest_index != null:
		var list = []
		latest_index = get_connected_lines_directional(list, overrides, root.down_direction, poly, latest_index, EdgeType.BOTTOM)
		if list.size() >= 2:
			generate_polygons(list, root.bottom, 2)

	# Now the sides.
	latest_index = 0
	while latest_index != null:
		var list = []
		# All edges' type indices have been marked now. Don't check angle,
		# just read the types we marked last time.
		latest_index = get_connected_lines_overrides(list, overrides, poly, latest_index, EdgeType.SIDE)
		if list.size() >= 2:
			generate_polygons(list, root.edge, 1)
