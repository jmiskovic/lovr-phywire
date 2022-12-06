# phywire

A library for visualizing and debugging [LÖVR](https://lovr.org/) physics.

In LÖVR framework the rendering is completely decoupled from phyisics simulation. User should query the physics sim for position and orientation of each collider (and each shape inside each collider) and render everything themselves. This library makes it easy to start of physical projects with simple rendering of each shape type with corresponding graphical primitive.

```Lua
phywire = require 'phywire'
world = lovr.physics.newWorld()
-- (create some colliders)

function lovr.draw(pass)
  phywire.draw(pass, world, phywire.render_shapes)  -- render solid geometry
  -- phywire.draw(pass, world)                      -- render in-depth visualizations
end
```

Aside from simple rendering of colliders, the library can visualize the physical simulation in various ways:

* draw wireframe shapes over existing rendered scene
* draw velocity vectors for each collider
* show angular velocity gizmos for each collider
* visualize the joints between colliders
* show information on collision contacts

## Customization

The third argument in `phywire.draw(pass, world, options)` receives a table with rendering *options*. When options are omitted, all the visualizations are utilized and the wireframe overdraw mode is selected.

Any visualization can be disabled by overriding some options:

```Lua
phywire.draw(pass, world, {
  show_shapes = true,           -- draw collider shapes (mesh and terrain not supported!)
  show_velocities = true,       -- vector showing direction and magnitude of collider linear velocity
  show_angulars = true,         -- gizmo displaying the collider's angular velocity
  show_joints = true,           -- show joints between colliders
  show_contacts = true,         -- show collision contacts (quite inefficient, triples the needed collision computations)
})
```

The `wireframe` flag is used to render shapes in wireframe mode. The `overdraw` flag disables the depth buffer test. This allows for useful combinations

* `{wireframe=false, overdraw=false}` draws solid geometry, provides quick and simple replacement for rendering of "physical" scene
* `{wireframe=true, overdraw=true}` renders on top of already drawn scene, this allows users to make sure their rendering is aligned with the physics state
* `{wireframe=true, overdraw=false}` still renders visualizations but respects existing scene geometry (visuals introduce less noise)

The library will assign a permanent color to each encountered shape from preselected palette. This is just convenience function for quickly throwing something onto the screen. Users can opt for their own color in two ways. They can override `shapes_palette` table in `options` with their own set of colors, without any control over what color is chosen for each shape. They can also specify individual colors while creating each shape inside each collider, and provide a map of shape colors into `shape_colors` table in `options`. Keys of this table are individual shapes, values are the colors used for that shape (either in `{r,g,b}` or hexcode format).

Various other options can be overriden, things like the scaling of each visualization type, sensitivities, and gizmo colors. Check the `m.options` table for more info.

The `phywire.render_shapes` table holds a preset for drawing the solid geometry of shapes without any other debugging visualizations; it can be given in place of *options* table.

## Limitations

Mesh shape and terrain shape types cannot be rendered by this library. The framework doesn't have the API to fetch geometry of these shapes. When encountered they will be skipped, but will print a warning in the console output.
