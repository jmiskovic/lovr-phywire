local m = {}

m.options = {
  -- drawing options
  wireframe = true,             -- show shapes in wireframe instead of filled geometry
  overdraw = true,              -- force elements to render over existing scene (ignore depth buffer check)
  show_shapes = true,           -- draw collider shapes (mesh and terrain not supported!)
  show_velocities = true,       -- vector showing direction and magnitude of collider linear velocity
  show_angulars = true,         -- gizmo displaying the collider's angular velocity
  show_joints = true,           -- show joints between colliders
  show_contacts = true,         -- show collision contacts (quite inefficient, triples the needed collision computations)
  geometry_segments = 9,        -- complexity of rendered geometry (number of segments in spheres, circles, cylinders, cones)
  -- sizes of visualized elements
  velocity_sensitivity = 0.1,   -- velocity multiplier to scale the displayed velocity vectors
  velocity_arrow_size = 0.002,
  angular_sensitivity = 4,      -- angular velocity multiplier for scaling the gizmo angles
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
  shape_colors = {}, -- table that maps a shape to color, if unspecified random color is selected
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
m.options.__index = m.options

m.render_shapes = { -- options preset for drawing filled shapes only
  wireframe = false,
  overdraw = false,
  show_shapes = true,
  show_velocities = false,
  show_angulars = false,
  show_joints = false,
  show_contacts = false,
  geometry_segments = 24,
}

m.next_color_index = 1 -- index of last chosen palette color
m.shown_warning = false

function m.drawShapes(pass, world, options)
  local tmat = mat4()
  for i, collider in ipairs(world:getColliders()) do
    for _, shape in ipairs(collider:getShapes()) do
      if not options.shape_colors[shape] then
        options.shape_colors[shape] = options.shapes_palette[m.next_color_index]
        m.next_color_index = 1 + (m.next_color_index % #options.shapes_palette)
      end
      pass:setColor(options.shape_colors[shape])
      local pose = tmat:set(collider:getPose()):translate(shape:getPosition()):rotate(shape:getOrientation())
      local shape_type = shape:getType()
      if shape_type == 'box' then
        pass:box(pose:scale(shape:getDimensions()))
      elseif shape_type == 'sphere' then
        pass:sphere(pose:scale(shape:getRadius()), options.geometry_segments, options.geometry_segments)
      elseif shape_type == 'cylinder' then
        local l, r = shape:getLength(), shape:getRadius()
        pass:cylinder(pose:scale(r, r, l), options.geometry_segments)
      elseif shape_type == 'capsule' then
        local l, r = shape:getLength(), shape:getRadius()
        pass:capsule(pose:scale(r, r, l), options.geometry_segments)
      elseif not m.shown_warning then -- not supported
        print('Warning: TerrainShape and MeshShape are not supported and will not be rendered')
        m.shown_warning = true
      end
    end
  end
end


function m.drawJoints(pass, world, options)
  pass:setColor(1,1,1)
  for i, collider in ipairs(world:getColliders()) do
    for j, joint in ipairs(collider:getJoints()) do
      local colliderA, colliderB = joint:getColliders()
      if collider == colliderA then
        local joint_type = joint:getType()
        if joint_type == 'ball' then
          local x1, y1, z1,  x2, y2, z2 = joint:getAnchors()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(vec3(x1, y1, z1), options.joint_anchor_size, options.geometry_segments)
          pass:sphere(vec3(x2, y2, z2), options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          pass:line(vec3(x1, y1, z1):lerp(x2, y2, z2, 0.05),
                    vec3(x1, y1, z1):lerp(x2, y2, z2, 0.95))
          pass:setColor(options.joint_label_color)
          local pose = mat4():target(vec3(x1, y1, z1):lerp(x2, y2, z2, 0.5), vec3(x2, y2, z2)):rotate(-math.pi/2, 0,1,0)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'slider' then
          local fraction = joint:getPosition()
          local ax, ay, az = joint:getAxis()
          local x1, y1, z1 = colliderA:getPosition()
          local x2, y2, z2 = colliderB:getPosition()
          pass:setColor(options.joint_axis_color)
          pass:line(vec3(x1, y1, z1), -- line from anchor down the axis
                    vec3(ax, ay, az):mul(options.joint_line_size):add(x1, y1, z1))
          pass:setColor(options.joint_label_color)
          local pose = mat4():target(vec3(x1, y1, z1):lerp(x2, y2, z2, 0.5), vec3(x2, y2, z2)):rotate(-math.pi/2, 0,1,0)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'distance' then
          local x1, y1, z1,  x2, y2, z2 = joint:getAnchors()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(vec3(x1, y1, z1), options.joint_anchor_size, options.geometry_segments)
          pass:sphere(vec3(x2, y2, z2), options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          pass:line(vec3(x1, y1, z1):lerp(x2, y2, z2, 0.05),
                    vec3(x1, y1, z1):lerp(x2, y2, z2, 0.95))
          pass:setColor(options.joint_label_color)
          local pose = mat4():target(vec3(x1, y1, z1):lerp(x2, y2, z2, 0.5), vec3(x2, y2, z2)):rotate(-math.pi/2, 0,1,0)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        elseif joint_type == 'hinge' then
          local x1, y1, z1,  x2, y2, z2 = joint:getAnchors() -- anchors are colocated when joint is satisfied
          local ax, ay, az = joint:getAxis()
          local angle = joint:getAngle()
          pass:setColor(options.joint_anchor_color)
          pass:sphere(vec3(x1, y1, z1), options.joint_anchor_size, options.geometry_segments)
          pass:sphere(vec3(x2, y2, z2), options.joint_anchor_size, options.geometry_segments)
          pass:setColor(options.joint_axis_color)
          pass:line(vec3(x1, y1, z1),  -- line from anchor down the axis
                    vec3(ax, ay, az):mul(options.joint_line_size):add(x1, y1, z1))
          pass:setColor(options.joint_label_color)
          local pose = mat4(x1, y1, z1,  -angle, ax, ay, az)
          pass:text(joint_type, pose:scale(options.joint_label_size))
        end
      end
    end
  end
end


function m.drawVelocities(pass, world, options)
  for i, collider in ipairs(world:getColliders()) do
    local pos = vec3(collider:getPosition())
    local vel = vec3(collider:getLinearVelocity())
    local mag = vel:length()
    pass:setColor(options.velocity_color)
    local pose = mat4():target(vel:mul(options.velocity_sensitivity) + pos, pos)
    pass:line(pos, vec3(pose))
    if mag > 1e-3 then
      pose:scale(options.velocity_arrow_size, options.velocity_arrow_size, -options.velocity_arrow_size * 2)
      pass:cone(pose, options.geometry_segments)
    end
  end
end


function m.drawAngulars(pass, world, options)
  local pose = mat4()
  for i, collider in ipairs(world:getColliders()) do
    local ang = vec3(collider:getAngularVelocity()):mul(options.angular_sensitivity)
     -- X axis
    pass:setColor(options.angular_x_color)
    pose:set(collider:getPose()) -- arc
    pose:rotate(math.pi / 2, 0,1,0)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, ang[1], options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(ang[1], 1,0,0)
    pose:translate(0, 0, -options.angular_gizmo_size)
    pose:rotate(-math.pi / 2, 1,0,0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (ang[1] < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
     -- Y axis
    pass:setColor(options.angular_y_color)
    pose:set(collider:getPose())  -- arc
    pose:rotate(-math.pi / 2, 1,0,0)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, ang[2], options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(math.pi, 0,1,0)
    pose:rotate(ang[2], 0,1,0)
    pose:translate(-options.angular_gizmo_size, 0, 0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (ang[2] < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
     -- Z axis
    pass:setColor(options.angular_z_color)
    pose:set(collider:getPose()) -- arc
    pose:rotate(math.pi / 2, 0,0,1)
    pass:circle(pose:scale(options.angular_gizmo_size), 'line', 0, ang[3], options.geometry_segments)
    pose:set(collider:getPose()) -- arrow
    pose:rotate(ang[3], 0,0,1)
    pose:translate(0, options.angular_gizmo_size, 0)
    pose:rotate(-math.pi / 2, 0,1,0)
    pose:scale(options.angular_gizmo_size, options.angular_gizmo_size, options.angular_gizmo_size * 2 * (ang[3] < 0 and 1 or -1)):scale(0.1)
    pass:cone(pose, options.geometry_segments)
  end
end


function m.drawCollisions(pass, world, options)
  world:update(0,
    function(world)
      world:computeOverlaps()
      for shapeA, shapeB in world:overlaps() do
        if world:collide(shapeA, shapeB) then
          local contacts = world:getContacts(shapeA, shapeB)
          for i,c in ipairs(contacts) do
            local x, y, z, nx, ny, nz, d = unpack(c)
            pass:setColor(options.collision_color)
            -- position of collision
            pass:sphere(x,y,z, options.collision_size, options.geometry_segments)
            -- normal
            pass:line(vec3(x,y,z),
                      vec3(nx, ny, nz):mul(options.collision_normal_length):add(x, y, z))
            -- calculated surface point of collision
            local pose = mat4():target(vec3(nx, ny, nz):mul(d):add(x, y, z), vec3(x, y, z))
            pose:scale(options.collision_size * 0.5, options.collision_size * 0.5, -options.collision_size)
            pass:cone(pose, options.geometry_segments)
          end
        end
      end
    end)
end


function m.draw(pass, world, options)
  options = setmetatable(options or {}, m.options)
  pass:push('state')
  if options.wireframe then
    pass:setWireframe(true)
    if options.overdraw then
      pass:setDepthTest()
    end
  end
  if options.show_shapes then     m.drawShapes(pass, world, options)     end
  pass:setWireframe(false) -- wireframe option only affects shapes
  if options.overdraw then
    pass:setDepthTest()
  end
  if options.show_joints then     m.drawJoints(pass, world, options)     end
  if options.show_velocities then m.drawVelocities(pass, world, options) end
  if options.show_angulars then   m.drawAngulars(pass, world, options)   end
  if options.show_contacts then   m.drawCollisions(pass, world, options) end
  pass:pop('state')
end


return m