-- grab and move colliders with mouse
local m = {}

m.range = 200
m.mouse_button = 2
m.near_plane = 0.01

m.draw_cursor = false

m.joint_uses_spring = false
m.joint_frequency = 2
m.joint_damping = 3

m.collider = nil   -- sensor collider synced to mouse movement needed for joint

local mouse_joint
local world_from_screen = Mat4()
local hovered = { depth = math.huge, collider = nil, position = Vec3() }

local function getWorldFromScreen(pass)
  local w, h = pass:getDimensions()
  local clip_from_screen = mat4(-1, -1, 0):scale(2 / w, 2 / h, 1)
  local view_pose = mat4(pass:getViewPose(1))
  local view_proj = pass:getProjection(1, mat4())
  local is_orthographic = view_proj[16] == 1
  local t = view_pose:mul(view_proj:invert()):mul(clip_from_screen)
  world_from_screen:set(t)
end


local function getRay(distance, pass)
  distance = distance or m.range
  local ray = {}
  local x, y = lovr.system.getMousePosition()
  ray.origin = vec3(world_from_screen:mul(x, y, m.near_plane / m.near_plane))
  ray.target = vec3(world_from_screen:mul(x, y, m.near_plane / distance))
  if is_orthographic then
    ray.origin.z = distance
    ray.target.z = -1000
  end
  return ray
end


function m.init(world)
  assert(world, 'Need to pass in the physics world object')
  m.collider = world:newSphereCollider(0, 0, 0, 0.1)
  m.collider:setKinematic(true)
  m.collider:setSensor(true)
end


function m.draw(pass)
  getWorldFromScreen(pass)
  local mx, my = lovr.system.getMousePosition()
  local origin = world_from_screen:mul(mx, my, m.near_plane / m.near_plane)
  local target = world_from_screen:mul(mx, my, m.near_plane / m.range)
  if not mouse_joint then
    hovered.collider = nil
    hovered.depth = math.huge
    local world = m.collider:getWorld()
    world:raycast(origin, target, nil,
      function(collider, shape, x, y, z, nx, ny, nz, fraction)
        local depth = origin:distance(x, y, z)
        if collider and not collider:isKinematic() and depth < hovered.depth then
          hovered.collider = collider
          hovered.depth = math.max(depth, 1e-5)
          hovered.position:set(x,y,z)
          m.collider:setPosition(x, y, z)
        end
        return 1
      end)
  else
    local cursor_pos = world_from_screen:mul(mx, my, m.near_plane / hovered.depth)
    m.collider:moveKinematic(cursor_pos, quat(), 1/8)
    local xa, ya, za, xb, yb, zb = mouse_joint:getAnchors()
    if m.draw_cursor then
      pass:setColor(1,1,1)
      pass:capsule(cursor_pos, vec3(xb, yb, zb), 0.01, 7)
    end
  end
end


function m.mousepressed(x, y, button)
  if button == m.mouse_button and hovered.collider then
    local pos = vec3(m.collider:getPosition())
    mouse_joint = lovr.physics.newDistanceJoint(hovered.collider, m.collider, hovered.position, hovered.position)
    if m.joint_uses_spring then
      mouse_joint:setSpring(m.joint_frequency, m.joint_damping)
    end
  end
end


function m.mousereleased(x, y, button)
  if button == m.mouse_button and mouse_joint then
    for _, joint in ipairs(m.collider:getJoints()) do
      joint:destroy()
      m.collider:setLinearVelocity(0)
    end
    mouse_joint = nil
  end
end


function m.wheelmoved(x, y)
  if not mouse_joint then return end
  hovered.depth = hovered.depth * (1 + 0.05 * y)
end


-- quickest way to use: call this in your lovr.load()
function m.integrate(world)
  m.init(world)
  local stub_fn = function() end
  local existing_cb = {
    draw = lovr.draw or stub_fn,
    mousepressed = lovr.mousepressed or stub_fn,
    mousereleased = lovr.mousereleased or stub_fn,
    wheelmoved = lovr.wheelmoved or stub_fn,
  }
  local function wrap(callback)
    return function(...)
      m[callback](...)
      existing_cb[callback](...)
    end
  end
  lovr.mousepressed = wrap('mousepressed')
  lovr.mousereleased = wrap('mousereleased')
  lovr.wheelmoved = wrap('wheelmoved')
  lovr.draw = function(pass)
    m.draw(pass)
    existing_cb.draw(pass)
  end
end

return m
