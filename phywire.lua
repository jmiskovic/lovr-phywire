-- library for visualizing lovr physics
local m = {}

-- default options table
m.options = {
  -- drawing options
  wireframe = false,             -- show shapes in wireframe instead of filled geometry
  overdraw = false,              -- force elements to render over existing scene (ignore depth buffer check)
  show_shapes = true,            -- draw collider shapes (mesh and terrain not supported!)
  show_outlines = false,         -- draw a thin outline around shapes, inked as darker tint of shape's color
  show_aabb = false,             -- draw each shape's axis-aligned boundary box
  show_velocities = false,       -- vector showing direction and magnitude of collider linear velocity
  show_angulars = false,         -- gizmo displaying the collider's angular velocity
  show_joints = false,           -- show joints between colliders
  show_contacts = false,         -- show collision contacts (quite inefficient, triples the needed collision computations)
  geometry_segments = 28,        -- complexity of rendered geometry (number of segments in spheres, circles, cylinders, cones)
  -- outline appearance
  outlines_width = 0.015,
  outlines_tint = 0.8,            -- controls how much the shape color is darkened in the shape outline
  outlines_depth_offset = -1e6,   -- depth buffer offset correction to push outlines inwards our outwards from camera
  outlines_depth_slope = -1,
  -- sizes of visualized elements
  velocity_sensitivity = 0.1,    -- velocity multiplier to scale the displayed velocity vectors
  velocity_arrow_size = 0.002,
  angular_sensitivity = 4,       -- angular velocity multiplier for scaling the gizmo angles
  angular_gizmo_size = 0.05,
  joint_label_size = 0.05,
  joint_anchor_size = 0.01,
  joint_line_size = 0.2,
  collision_size = 0.01,
  collision_normal_length = 0.1,
  -- colors of visualizations
  velocity_color = {0.878, 0.784, 0.447},
  joint_anchor_color = {0.169, 0.157, 0.129},
  joint_axis_color = {0.890, 0.812, 0.706, 0.2},
  joint_label_color = {0.694, 0.647, 0.553},
  collision_color = {0.690, 0.227, 0.282},

  angular_x_color = {0.631, 0.231, 0.227},
  angular_y_color = {0.247, 0.427, 0.224},
  angular_z_color = {0.141, 0.239, 0.361},
  shapes_palette = { -- list of colors to be assigned to each shape not specified in shape_colors
    {0.180, 0.133, 0.184}, -- https://lospec.com/palette-list/mushroom
    {0.600, 0.239, 0.255},
    {0.471, 0.541, 0.529},
    {0.341, 0.376, 0.412},
    {0.267, 0.220, 0.275},
    {0.400, 0.349, 0.392},
    {0.271, 0.161, 0.247},
    {0.478, 0.188, 0.271},
    {0.663, 0.698, 0.635},
    {0.804, 0.408, 0.239},
    {0.949, 0.925, 0.545},
    {0.984, 0.725, 0.329},
    {0.690, 0.663, 0.529},
    {0.600, 0.498, 0.451},
  }
}

m.shape_colors = {} -- maps a shape to a specific color
m.meshFromConvex = {} -- maps convex shapes to their extracted meshes
m.next_color_index = 1 -- index of last chosen palette color
m.shown_warning = false
m.specified_draw_fns = {} -- maps shapes or colliders to custom draw functions


local aabb_points = {}
for i = 1, 8 do
  aabb_points[i] = vector(0, 0, 0)
end


local function readColor(...)
  local color = { 1, 1, 1, 1 }
  local args = { ... }
  local numArgs = select('#', ...)
  if type(args[1]) == 'table' then -- color in the table: {r, g, b, a}
    local t = args[1]
    color[1] = t[1] or 1
    color[2] = t[2] or 1
    color[3] = t[3] or 1
    color[4] = t[4] or 1
  elseif numArgs >= 3 then -- direct r, g, b components as arguments
    color[1] = args[1]
    color[2] = args[2]
    color[3] = args[3]
    color[4] = args[4] or 1
  else                    -- hex color
    local hex = args[1]
    local r = bit.band(bit.rshift(hex, 16), 0xFF)
    local g = bit.band(bit.rshift(hex, 8), 0xFF)
    local b = bit.band(hex, 0xFF)
    color[1] = r / 255
    color[2] = g / 255
    color[3] = b / 255
    color[4] = args[2] or 1
  end
  return color[1], color[2], color[3], color[4]
end


function m.setColor(shape_or_collider, color)
  if shape_or_collider.getType then
    local shape = shape_or_collider
    m.shape_colors[shape] = color
  elseif shape_or_collider.getShapes then
    local collider = shape_or_collider
    for _, shape in ipairs(collider:getShapes()) do
      m.shape_colors[shape] = color
    end
  else
    error('setColor must receive Shape or Collider instance as 1st argument')
  end
end


function m.setDraw(shape_or_collider, draw_fn)
  assert(shape_or_collider.getType or shape_or_collider.getShapes,
    'setDraw must receive Shape or Collider instance as 1st argument')
  m.specified_draw_fns[shape_or_collider] = draw_fn
end


function m.setIgnored(shape_or_collider)
  m.specified_draw_fns[shape_or_collider] = 'skip'
end


function m.fromConvexShape(shape)
  local function updateNormals(vertices, indices)
    if not indices then
      indices = {}
      for i = 1, #vertices do
        indices[i] = i
      end
    end
    if #indices < 3 then return end
    local normals = {} -- maps vertex index to list of normals of adjacent faces
    for i = 1, #indices, 3 do
      local vi1, vi2, vi3 = indices[i], indices[i + 1], indices[i + 2]
      local v1 = vector(unpack(vertices[vi1]))
      local v2 = vector(unpack(vertices[vi2]))
      local v3 = vector(unpack(vertices[vi3]))
      local fnormal = (v2 - v1):cross(v3 - v1):normalize()
      normals[vi1] = normals[vi1] or {}
      normals[vi2] = normals[vi2] or {}
      normals[vi3] = normals[vi3] or {}
      table.insert(normals[vi1], fnormal)
      table.insert(normals[vi2], fnormal)
      table.insert(normals[vi3], fnormal)
    end
    for i = 1, #vertices do
      if normals[i] then
        local vnormal = vector(0, 0, 0)
        local c = 0
        for _, fnormal in ipairs(normals[i]) do
          vnormal = vnormal + fnormal
          c = c + 1
        end
        local vn = (vnormal * (1 / c)):normalize()
        local v = vertices[i]
        local nx, ny, nz = vn:unpack()
        v[4], v[5], v[6] = nx, ny, nz
      end
    end
  end
  local vertices, indices = {}, {}
  for i = 1, shape:getPointCount() do
    local x, y, z = shape:getPoint(i)
    table.insert(vertices, { x, y, z })
  end
  for i = 1, shape:getFaceCount() do
    local face_indices = shape:getFace(i)
    for j = 2, #face_indices - 1 do
      table.insert(indices, face_indices[1])
      table.insert(indices, face_indices[j])
      table.insert(indices, face_indices[j + 1])
    end
  end
  updateNormals(vertices, indices)
  local mesh = lovr.graphics.newMesh({
    { 'VertexPosition', 'vec3' },
    { 'VertexNormal',   'vec3' },
  }, vertices, 'gpu')
  mesh:setIndices(indices)
  mesh:computeBoundingBox()
  return mesh
end


function m.drawCollider(pass, collider)
  local collider_pose = mat4(collider:getPose())
  local collider_draw_fn = m.specified_draw_fns[collider]
  if collider_draw_fn then
    if collider_draw_fn ~= 'skip' then
      pass:setColor(1, 1, 1)
      collider_draw_fn(pass, collider_pose)
    end
    return -- skip the individual shapes of this collider
  end
  local options = m.options
  local segments = options.geometry_segments

  for _, shape in ipairs(collider:getShapes()) do
    local pose = collider_pose * mat4(shape:getOffset())
    local shape_draw_fn = m.specified_draw_fns[shape]
    if shape_draw_fn then
      if shape_draw_fn ~= 'skip' then
        pass:setColor(1, 1, 1)
        shape_draw_fn(pass, pose)
      end
    else
      if not m.shape_colors[shape] then
        m.shape_colors[shape] = options.shapes_palette[m.next_color_index]
        m.next_color_index = 1 + (m.next_color_index % #options.shapes_palette)
      end
      pass:setColor(m.shape_colors[shape])
      local shape_type = shape:getType()
      if shape_type == 'box' then
        pass:box(pose:scale(shape:getDimensions()))
      elseif shape_type == 'sphere' then
        pose:scale(shape:getRadius())
        pass:sphere(pose, segments, segments)
      elseif shape_type == 'cylinder' then
        local l, r = shape:getLength(), shape:getRadius()
        pose:scale(r, r, l)
        pass:cylinder(pose, true, 0, 2 * math.pi, segments)
      elseif shape_type == 'capsule' then
        local l, r = shape:getLength(), shape:getRadius()
        pose:scale(r, r, l)
        pass:capsule(pose, segments)
      elseif shape_type == 'convex' then
        if not m.meshFromConvex[shape] then
          m.meshFromConvex[shape] = m.fromConvexShape(shape)
        end
        pass:draw(m.meshFromConvex[shape], pose)
      else
        if not m.shown_warning then -- not supported
          print('Warning: TerrainShape and MeshShape are not supported and will not be rendered')
          m.shown_warning = true
        end
      end
    end
    m.drawn_shapes = m.drawn_shapes + 1
  end
end


function m.drawOutlines(pass, world)
  local options = m.options
  pass:setCullMode('back')
  pass:setDepthOffset(options.outlines_depth_offset, options.outlines_depth_slope)

  local segments = options.geometry_segments
  local w = options.outlines_width
  local t = options.outlines_tint

  for _, collider in ipairs(world:getColliders()) do
    local collider_draw_fn = m.specified_draw_fns[collider]
    if not collider_draw_fn then
      local collider_pose = mat4(collider:getPose())
      for _, shape in ipairs(collider:getShapes()) do
        local shape_draw_fn = m.specified_draw_fns[shape]
        if not shape_draw_fn then
          local pose = collider_pose * mat4(shape:getOffset())
          local shape_type = shape:getType()
          local shape_color = m.shape_colors[shape] or { 1, 1, 1 }
          local r, g, b = readColor(shape_color)
          pass:setColor(r * t, g * t, b * t)
          if shape_type == 'box' then
            local sx, sy, sz = shape:getDimensions()
            pose:scale(sx + w * 2, sy + w * 2, sz + w * 2)
            pose:scale(-1)
            pass:box(pose)
          elseif shape_type == 'sphere' then
            pose:scale(shape:getRadius())
            pose:scale(-(1 + w * 2))
            pass:sphere(pose, segments, segments)
          elseif shape_type == 'cylinder' then
            local l, r = shape:getLength(), shape:getRadius()
            pose:scale(r + w, r + w, l + 2 * w)
            pose:scale(-1)
            pass:cylinder(pose, true, 0, 2 * math.pi, segments)
          elseif shape_type == 'capsule' then
            local l, r = shape:getLength(), shape:getRadius()
            pose:scale(r + w, r, l - w / 2)
            pose:scale(-1)
            pass:capsule(pose, segments)
          elseif shape_type == 'convex' then
            local mesh = m.meshFromConvex[shape]
            if mesh then
              pose:mul(mat4(shape:getCenterOfMass()))
              pose:scale(1 + w)
              pass:setDepthOffset(1)
              pass:draw(mesh, pose)
              pass:setDepthOffset()
            end
          end
        end
      end
    end
  end
  pass:setDepthOffset()
end


function m.drawShapes(pass, world)
  m.drawn_shapes = 0
  for _, collider in ipairs(world:getColliders()) do
    m.drawCollider(pass, collider)
  end
end


function m.drawAABBs(pass, world)
  pass:setColor(1, 1, 1, 0.2)
  for _, collider in ipairs(world:getColliders()) do
    for _, shape in ipairs(collider:getShapes()) do
      local minx, maxx, miny, maxy, minz, maxz = shape:getAABB()
      pass:box(
        (minx + maxx) / 2, -- x
        (miny + maxy) / 2, -- y
        (minz + maxz) / 2, -- z
        maxx - minx, -- w
        maxy - miny, -- h
        maxz - minz, -- d
        0, 0, 0, 0,
        'line')
    end
  end
end


function m.drawJoints(pass, world)
  local options = m.options
  pass:setColor(1, 1, 1)
  for _, collider in ipairs(world:getColliders()) do
    for _, joint in ipairs(collider:getJoints()) do
      local colliderA, colliderB = joint:getColliders()
      if collider == colliderA then
        local joint_type = joint:getType()
        if joint_type == 'ball' then
          local x1, y1, z1, x2, y2, z2 = joint:getAnchors()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(x1, y1, z1, options.joint_anchor_size, options.geometry_segments)
          pass:sphere(x2, y2, z2, options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_label_color)
          local pose = mat4(x1, y1, z1):scale(options.joint_label_size)
          pass:text(joint_type, pose)
        elseif joint_type == 'slider' then
          local ax, ay, az = joint:getAxis()
          local x1, y1, z1 = colliderA:getPosition()
          local x2, y2, z2 = colliderB:getPosition()
          pass:setColor(options.joint_axis_color)
          local ex, ey, ez = (vector(ax, ay, az) * options.joint_line_size + vector(x1, y1, z1)):unpack()
          pass:line(x1, y1, z1, ex, ey, ez)
          pass:setColor(options.joint_label_color)
          local mid = vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.5)
          local pose = mat4():target(mid, vector(x2, y2, z2)):rotate(-math.pi / 2, 0, 1, 0)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'distance' then
          local x1, y1, z1, x2, y2, z2 = joint:getAnchors()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(x1, y1, z1, options.joint_anchor_size, options.geometry_segments)
          pass:sphere(x2, y2, z2, options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          local a = vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.05)
          local b = vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.95)
          local ax1, ay1, az1 = a:unpack()
          local bx1, by1, bz1 = b:unpack()
          pass:line(ax1, ay1, az1, bx1, by1, bz1)
          pass:setColor(options.joint_label_color)
          local pose = mat4()
          pose:target(vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.5), vector(x2, y2, z2))
          pose:rotate(-math.pi / 2, 0, 1, 0)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'hinge' then
          local x1, y1, z1, x2, y2, z2 = joint:getAnchors()
          local ax, ay, az = joint:getAxis()
          local angle = joint:getAngle()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(x1, y1, z1, options.joint_anchor_size, options.geometry_segments)
          pass:sphere(x2, y2, z2, options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          local end_axis = vector(ax, ay, az) * options.joint_line_size + vector(x1, y1, z1)
          local ex, ey, ez = end_axis:unpack()
          pass:line(x1, y1, z1, ex, ey, ez)
          pass:setColor(options.joint_label_color)
          local pose = mat4(end_axis, -angle, ax, ay, az)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'weld' then
          local x1, y1, z1, x2, y2, z2 = joint:getAnchors()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(x1, y1, z1, options.joint_anchor_size, options.geometry_segments)
          pass:sphere(x2, y2, z2, options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          local a = vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.05)
          local b = vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.95)
          local ax1, ay1, az1 = a:unpack()
          local bx1, by1, bz1 = b:unpack()
          pass:line(ax1, ay1, az1, bx1, by1, bz1)
          pass:setColor(options.joint_label_color)
          local pose = mat4(vector(x1, y1, z1):lerp(vector(x2, y2, z2), 0.5), colliderA:getOrientation())
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'cone' then
          local ax, ay, az = joint:getAxis()
          local x1, y1, z1 = colliderA:getPosition()
          local x2, y2, z2 = colliderB:getPosition()
          pass:setColor(options.joint_axis_color)
          local ex, ey, ez = (vector(ax, ay, az) * options.joint_line_size + vector(x1, y1, z1)):unpack()
          pass:line(x1, y1, z1, ex, ey, ez)
          pass:setColor(options.joint_label_color)
          local pose = mat4():target(vector(x1, y1, z1), vector(x1 + ax, y1 + ay, z1 + az))
          if (vector(x2, y2, z2) - vector(x1, y1, z1)):dot(vector(ax, ay, az)) > 0 then
            pose:rotate(math.pi, 0, 1, 0)
          end
          pass:text(joint_type, mat4(pose):scale(options.joint_label_size))
          pose:translate(0, 0, options.joint_line_size)
          local r = math.atan(joint:getLimit()) * options.joint_line_size
          pass:cone(mat4(pose):scale(r, r, options.joint_line_size), options.geometry_segments)
        end
      end
    end
  end
end


function m.drawVelocities(pass, world)
  local options = m.options
  for _, collider in ipairs(world:getColliders()) do
    local pos = vector(collider:getPosition())
    local vel = vector(collider:getLinearVelocity())
    local mag = vel:length()
    pass:setColor(options.velocity_color)
    local tip = pos + vel * options.velocity_sensitivity
    local x1, y1, z1 = pos:unpack()
    local x2, y2, z2 = tip:unpack()
    pass:line(x1, y1, z1, x2, y2, z2)
    if mag > 1e-3 then
      local pose = mat4():target(tip, pos)
      pose:scale(options.velocity_arrow_size, options.velocity_arrow_size, -options.velocity_arrow_size * 2)
      pass:cone(pose, options.geometry_segments)
    end
  end
end


function m.drawAngulars(pass, world)
  local options = m.options
  local pose = mat4()
  for _, collider in ipairs(world:getColliders()) do
    local ang = vector(collider:getAngularVelocity()) * options.angular_sensitivity
    local ax, ay, az = ang:unpack()
     -- X axis
    pass:setColor(options.angular_x_color)
    pose:set(collider:getPose()) -- arc
    pose:rotate(math.pi / 2, 0, 1, 0)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, ax, options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(ax, 1, 0, 0)
    pose:translate(0, 0, -options.angular_gizmo_size)
    pose:rotate(-math.pi / 2, 1, 0, 0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (ax < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
     -- Y axis
    pass:setColor(options.angular_y_color)
    pose:set(collider:getPose())  -- arc
    pose:rotate(-math.pi / 2, 1, 0, 0)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, ay, options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(math.pi, 0, 1, 0)
    pose:rotate(ay, 0, 1, 0)
    pose:translate(-options.angular_gizmo_size, 0, 0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (ay < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
     -- Z axis
    pass:setColor(options.angular_z_color)
    pose:set(collider:getPose()) -- arc
    pose:rotate(math.pi / 2, 0, 0, 1)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, az, options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(az, 0, 0, 1)
    pose:translate(0, options.angular_gizmo_size, 0)
    pose:rotate(-math.pi / 2, 0, 1, 0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (az < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
  end
end


function m.drawCollisions(pass, world)
  -- TODO
end


function m.draw(pass, world)
  local options = m.options
  pass:push('state')
  if options.wireframe then
    pass:setWireframe(true)
    if options.overdraw then
      pass:setDepthTest()
    end
  end
  if options.show_shapes then     m.drawShapes(pass, world)     end
  if options.show_aabb then       m.drawAABBs(pass, world)      end
  if options.overdraw then
    pass:setDepthTest()
  end
  pass:setWireframe(false)
  pass:setShader() -- drawing text and other gizmos with default shader
  if options.show_joints then     m.drawJoints(pass, world)     end
  if options.show_velocities then m.drawVelocities(pass, world) end
  if options.show_angulars then   m.drawAngulars(pass, world)   end
  if options.show_contacts then   m.drawCollisions(pass, world) end
  if options.show_outlines and not options.wireframe then m.drawOutlines(pass, world)   end
  pass:pop('state')
end


function m.xray(pass, world, resolution)
  resolution = resolution or 0.01
  local NEAR_PLANE = 0.01
  local w, h = pass:getDimensions()
  local clip_from_screen = mat4(-1, -1, 0):scale(2 / w, 2 / h, 1)
  local view_pose = mat4(pass:getViewPose(1))
  local view_proj = pass:getProjection(1, mat4())
  local world_from_screen = view_pose:mul(view_proj:invert()):mul(clip_from_screen)
  for sx = 0, w, w * resolution do
    for sy = 0, h, h * resolution do
      local origin = world_from_screen * vector(sx, sy, NEAR_PLANE / NEAR_PLANE)
      local target = world_from_screen * vector(sx, sy, NEAR_PLANE / 100)
      local collider, shape, x, y, z, nx, ny, nz, f = world:raycast(origin, target)
      if collider then
        pass:cube(x, y, z, resolution)
      end
    end
  end
end

return m
