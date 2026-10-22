"""Build original low-poly game models. Run with Blender in background mode."""
import bpy
import math
import os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)

MATERIALS = {}
def mat(name, rgb, metallic=0.0, roughness=0.65, emission=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Base Color"].default_value = (*rgb, 1)
    bs.inputs["Metallic"].default_value = metallic
    bs.inputs["Roughness"].default_value = roughness
    if emission:
        bs.inputs["Emission Color"].default_value = (*rgb, 1)
        bs.inputs["Emission Strength"].default_value = emission
    MATERIALS[name] = m
    return m

coal = mat("Charcoal iron", (.105,.12,.16), .55)
iron = mat("Polished silver", (.56,.63,.67), .8, .28)
gold = mat("Antique gold", (.74,.46,.22), .65, .32)
cream = mat("Warm bone", (.78,.70,.58))
red = mat("Ember cloak", (.48,.17,.15))
red_dark = mat("Cloak shadow", (.26,.10,.13))
flame = mat("Living ember", (1.0,.42,.11), .0, .25, 3.0)
flame_core = mat("Flame core", (1.0,.82,.35), .0, .25, 4.0)
ghost = mat("Wraith violet", (.29,.23,.40), .15)
ghost_light = mat("Wraith highlight", (.48,.37,.59), .1)
cyan = mat("Wraith eyes", (.37,.88,.95), 0, .2, 3.0)
stone = mat("Carved stone", (.27,.28,.34))
stone_light = mat("Stone edge", (.43,.41,.42))
moss = mat("Ancient moss", (.26,.38,.32))

def cube(name, loc, scale, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object;o.name=name;o.dimensions=scale;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new("Hand cut edges", "BEVEL");mod.width=bevel;mod.segments=1
        o.modifiers.new("Weighted normals", "WEIGHTED_NORMAL")
    o.data.materials.append(material)
    return o

def ico(name, loc, radius, material, subdivisions=1, scale=None):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions,radius=radius,location=loc)
    o=bpy.context.object;o.name=name
    if scale:o.scale=scale
    o.data.materials.append(material)
    return o

def cone(name, loc, r1, r2, depth, material, vertices=8):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=depth,location=loc)
    o=bpy.context.object;o.name=name;o.data.materials.append(material);return o

def torus(name, loc, major, minor, material, rotation=(0,0,0)):
    bpy.ops.mesh.primitive_torus_add(major_segments=16,minor_segments=4,location=loc,rotation=rotation,major_radius=major,minor_radius=minor)
    o=bpy.context.object;o.name=name;o.data.materials.append(material);return o

def clear():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)

def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,name+".glb"), export_format="GLB",use_selection=True,export_apply=True)
    print("Exported",name)

# The ember knight: angular hood, cloak, breastplate, boots, sword and lantern.
clear()
cone("Layered cloak",(0,.10,1.05),.52,.29,1.25,red,7)
cone("Inner cloak",(0,.16,.81),.45,.22,.72,red_dark,7)
cube("Breastplate",(0,-.18,1.35),(.62,.43,.65),coal,.10)
cube("Gold breastplate trim",(0,-.42,1.43),(.48,.05,.07),gold,.015)
ico("Head",(0,-.06,1.88),.29,cream,1, (1,.9,1.12))
cone("Deep hood",(0,.08,2.04),.36,.03,.67,coal,7)
cube("Visor shadow",(0,-.295,1.91),(.42,.07,.18),red_dark,.03)
for side in (-1,1):
    cube("Glowing eye",(side*.105,-.337,1.92),(.075,.02,.044),flame_core,.008)
    cube("Arm",(side*.42,-.03,1.32),(.23,.26,.59),coal,.06)
    ico("Pauldron",(side*.44,-.02,1.66),.24,iron,1,(1,.88,.67))
    cube("Boot",(side*.20,-.15,.36),(.25,.37,.64),coal,.045)
    cube("Boot cap",(side*.20,-.33,.13),(.27,.23,.22),iron,.035)
cube("Sword grip",(.62,-.04,.96),(.10,.12,.45),gold,.025)
cube("Sword guard",(.62,-.04,1.22),(.42,.11,.08),gold,.02)
cube("Sword blade",(.62,-.04,1.71),(.16,.065,.92),iron,.018)
cone("Sword tip",(.62,-.04,2.21),.09,0,.22,iron,4)
export("ember_knight")

# Shadow enemy.
clear()
cone("Tattered robe",(0,0,.75),.5,.28,1.3,ghost,7)
cone("Floating inner shroud",(0,-.02,.49),.38,.15,.59,ghost_light,7)
ico("Hollow skull",(0,-.08,1.6),.34,ghost_light,1,(1,.9,1.2))
cone("Dark cowl",(0,.07,1.75),.43,.04,.66,ghost,7)
cube("Face abyss",(0,-.36,1.59),(.48,.08,.25),coal,.04)
for side in (-1,1):
    ico("Eye",(side*.11,-.42,1.62),.055,cyan,1,(1,.45,.6))
    cone("Claw sleeve",(side*.48,-.04,1.08),.19,.1,.64,ghost,6)
    cone("Claw",(side*.53,-.25,.67),.095,0,.41,stone_light,5)
export("shade")

# Heavy guardian enemy.
clear()
cone("Bulky torso",(0,0,1.1),.69,.44,1.25,stone,8)
cube("Iron chest",(0,-.42,1.22),(.95,.19,.65),coal,.10)
cube("Chest sigil",(0,-.54,1.29),(.15,.04,.45),flame,.025)
ico("Helmet",(0,-.02,1.95),.44,coal,1,(1,.9,.9))
cube("Visor",(0,-.4,1.91),(.62,.15,.17),red_dark,.04)
for side in (-1,1):
    cone("Horn",(side*.37,.0,2.34),.16,0,.73,cream,6)
    cube("Glowing slit",(side*.15,-.49,1.93),(.12,.02,.06),flame,.008)
    ico("Shoulder",(side*.68,0,1.52),.34,stone_light,1,(1,.9,.72))
    cube("Heavy arm",(side*.72,-.04,.95),(.37,.39,.92),stone,.07)
    cube("Leg",(side*.30,0,.35),(.42,.47,.69),coal,.07)
export("guardian")

# Shrine.
clear()
cone("Plinth base",(0,0,.15),.95,.81,.3,stone,8)
cone("Carved step",(0,0,.42),.75,.68,.35,stone_light,8)
cone("Altar",(0,0,.77),.48,.35,.46,stone,8)
torus("Rune ring",(0,0,1.04),.44,.055,gold)
ico("Suspended ember",(0,0,1.35),.24,flame_core,1)
for a in range(8):
    angle=a*math.tau/8
    cube("Rune",(.57*math.cos(angle),.57*math.sin(angle),.61),(.09,.09,.13),gold,.02)
export("shrine")

# Torch / brazier.
clear()
cone("Iron foot",(0,0,.11),.36,.31,.22,coal,8)
cone("Stem",(0,0,.53),.13,.10,.75,iron,8)
cone("Fire bowl",(0,0,.93),.35,.24,.22,coal,8)
torus("Bowl rim",(0,0,1.04),.33,.04,gold)
ico("Fire low",(0,0,1.18),.22,flame,1,(.9,.9,1.25))
cone("Fire tip",(0,0,1.46),.16,0,.43,flame_core,6)
export("brazier")

# Stone obelisk used as room cover.
clear()
cone("Octagonal foot",(0,0,.18),.54,.49,.36,stone,8)
cone("Ancient pillar",(0,0,1.0),.37,.30,1.55,stone_light,8)
cone("Broken crown",(0,0,1.84),.45,.39,.21,stone,8)
for i in range(4):
    a=math.pi*.25+i*math.pi*.5
    cube("Moss seam",(.31*math.cos(a),.31*math.sin(a),.72),(.09,.10,.7),moss,.01)
export("pillar")

clear()
