extends RefCounted

const SkyBackdrop = preload("res://scripts/sky_backdrop.gd")
const ATLAS = preload("res://assets/HIRO.png")
const NORMALS := [Vector3i(0,0,-1), Vector3i(1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(-1,0,0), Vector3i(0,0,1)]
var data: Dictionary
var atlas_material: StandardMaterial3D
var ball_material: ShaderMaterial
var cache: Dictionary = {}

func _init() -> void:
    data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/level1_visuals.json"))
    atlas_material = StandardMaterial3D.new()
    atlas_material.albedo_texture = ATLAS
    atlas_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    atlas_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
    atlas_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    var shader := Shader.new()
    shader.code = "shader_type spatial; render_mode unshaded, cull_back; void fragment(){float light=clamp(0.348+0.96*dot(normalize(NORMAL),normalize(vec3(-1.0,4.0,2.0))),0.348,1.0); ALBEDO=COLOR.rgb*light;}"
    ball_material = ShaderMaterial.new()
    ball_material.shader = shader

func model(type: String, variant: int = 0) -> ArrayMesh:
    var key := type + ":" + str(variant)
    if cache.has(key):
        return cache[key]
    var source: Dictionary = data["ball"] if type == "ball" else data["models"][type][variant]
    var mesh := ArrayMesh.new()
    for transparent in [false, true]:
        var st := SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
        var count := 0
        for k in range(source["polys"].size()):
            var flags := int(source["flags"][k])
            if bool(flags & 2) != transparent:
                continue
            var polygon: Array = source["polys"][k]
            var triangles: Array = [0,2,1,1,2,3] if polygon.size() == 4 else [0,2,1]
            for corner in triangles:
                var index := int(polygon[corner])
                var raw: Array = source["frames"][0]
                var vertex := Vector3(raw[index*3],raw[index*3+1],raw[index*3+2]) / 512.0
                var n := vertex.normalized()
                if source.has("normals"):
                    var normals: Array = source["normals"]
                    n = Vector3(normals[index*3],normals[index*3+1],normals[index*3+2]).normalized()
                var rgb: Array = source["rgb"][k]
                var color_index: int = corner*3 if flags & 16 else 0
                st.set_color(Color(rgb[color_index]/255.0,rgb[color_index+1]/255.0,rgb[color_index+2]/255.0,0.4 if transparent else 1.0))
                st.set_normal(n)
                st.add_vertex(vertex)
                count += 1
        if count == 0:
            continue
        var material: Material
        if type == "ball":
            material = ball_material
        else:
            var flat := StandardMaterial3D.new()
            flat.vertex_color_use_as_albedo = true
            flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            flat.cull_mode = BaseMaterial3D.CULL_DISABLED
            if transparent:
                flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
                if int(source.get("blend",0)) == 3:
                    flat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
            material = flat
        st.set_material(material)
        st.commit(mesh)
    cache[key] = mesh
    return mesh

func cube(original: Vector3i, occupied: Dictionary, objects: Array, portal_open: bool) -> ArrayMesh:
    var mesh := ArrayMesh.new()
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for face in range(6):
        var up: Vector3i = NORMALS[face]
        if occupied.has(_world(original+up)):
            continue
        var tex: int = abs(original.x*73856093 ^ original.y*19349663 ^ original.z*83492791 ^ (face+1)*2971215073) % 4
        var source_type := 0
        for object in objects:
            if object["cell"] == _world(original) and object["normal"] == _world(up):
                source_type = {"portal":7,"key":31,"coin":37,"fruit":43,"start":30}.get(object["kind"],0)
                break
        if source_type != 0:
            var frames: Array = data["skins"]["sets"]["arcade"]["types"][str(source_type)]
            tex = int(frames[1 if source_type != 7 or portal_open else 0])
        var shade := int(data["skins"]["shade"]["HIRO"][face])
        var corners: Array = data["skins"]["corners"][face][0]
        var uvs := [Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1)]
        for index in [0,1,2,1,3,2]:
            var point: Array = corners[index]
            st.set_normal(Vector3(_world(up)))
            st.set_uv(Vector2((tex*64.0+0.5+uvs[index].x*63.0)/3584.0,(shade*64.0+0.5+uvs[index].y*63.0)/192.0))
            st.add_vertex(Vector3(point[0]-0.5, -(point[2]-0.5), point[1]-0.5))
    st.set_material(atlas_material)
    st.commit(mesh)
    return mesh

func _world(at: Vector3i) -> Vector3i:
    return Vector3i(at.x,-at.z,at.y)

func environment(parent: Node3D) -> Node3D:
    var world := WorldEnvironment.new()
    world.environment = Environment.new()
    world.environment.background_mode = Environment.BG_COLOR
    world.environment.background_color = Color.BLACK
    world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    world.environment.ambient_light_color = Color(0.94,0.84,0.66)
    world.environment.ambient_light_energy = 0.8
    parent.add_child(world)
    var backdrop = SkyBackdrop.new()
    backdrop.name = "OriginalHiroBackdrop"
    parent.add_child(backdrop)
    return backdrop
