extends Node3D

const BANDS := 24
const SEGMENTS := 48
const RADIUS := 100.0
const PANORAMA = preload("res://assets/HIRO-panorama.webp")
var sphere: MeshInstance3D
var material: ShaderMaterial

func _ready() -> void:
    sphere = MeshInstance3D.new()
    sphere.name = "HiroPanorama"
    sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    sphere.mesh = _sphere_mesh()
    var shader := Shader.new()
    shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform sampler2D panorama : source_color, filter_nearest, repeat_disable;
varying vec2 affine_uv;
varying float affine_w;
void vertex(){
    vec4 clip=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.0);
    affine_uv=UV*clip.w;
    affine_w=clip.w;
}
void fragment(){
    vec2 uv=affine_uv/max(affine_w,0.00001);
    ALBEDO=texture(panorama,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
}
"""
    material = ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("panorama",PANORAMA)
    sphere.material_override = material
    add_child(sphere)

func follow(camera: Camera3D) -> void:
    global_position = camera.global_position

func _sphere_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for band in range(BANDS):
        var v0 := float(band)/BANDS
        var v1 := float(band+1)/BANDS
        for segment in range(SEGMENTS):
            var u0 := float(segment)/SEGMENTS
            var u1 := float(segment+1)/SEGMENTS
            var uv := [Vector2(u0,v0),Vector2(u1,v0),Vector2(u0,v1),Vector2(u1,v1)]
            for corner in [0,1,2,1,3,2]:
                var sample: Vector2 = uv[corner]
                var point := _point(sample)
                st.set_uv(sample)
                st.set_normal(-point.normalized())
                st.add_vertex(point)
    return st.commit()

func _point(uv: Vector2) -> Vector3:
    var latitude := uv.y*PI
    var longitude := (uv.x-0.5)*TAU
    return Vector3(sin(latitude)*sin(longitude),cos(latitude),-sin(latitude)*cos(longitude))*RADIUS
