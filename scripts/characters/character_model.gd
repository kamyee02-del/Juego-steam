class_name ModeloPersonaje
extends Node3D
## Monta un personaje de KayKit con sus animaciones y decide cuál reproducir.
##
## Los personajes vienen sin animaciones: éstas están en archivos aparte que
## comparten el mismo esqueleto ("Rig_Medium"). Como las pistas apuntan a
## "Rig_Medium/Skeleton3D:hueso" y los personajes tienen justo esa estructura,
## basta con colgar un AnimationPlayer del modelo y añadirle las librerías.

## Modelos disponibles. Los rehenes van rotando por esta lista para que cada
## jugador tenga un aspecto distinto; el guardia usa el caballero.
const REHENES: Array[String] = [
	"Rogue_Hooded", "Rogue", "Ranger", "Mage", "Barbarian", "Knight",
]
const GUARDIA := "Knight"

const LIBRERIAS := [
	"res://assets/characters/animations/Rig_Medium_MovementBasic.glb",
	"res://assets/characters/animations/Rig_Medium_General.glb",
]

## Los modelos miden unas 2,2 unidades; el cuerpo físico del juego mide 1,8.
const ESCALA := 0.8
const FUNDIDO := 0.15

# Nombres de animación tal como vienen en el pack.
const QUIETO := "Idle_A"
const ANDAR := "Walking_A"
const CORRER := "Running_A"
const AGACHADO_QUIETO := "Idle_B"
const INTERACTUAR := "Interact"
const LANZAR := "Throw"
const CAER := "Death_A_Pose"

var _anim: AnimationPlayer
var _modelo: Node3D
var _actual := ""


## Construye el personaje indicado. Devuelve false si el modelo no existe.
func montar(nombre: String) -> bool:
	var ruta := "res://assets/characters/%s.glb" % nombre
	if not ResourceLoader.exists(ruta):
		push_error("No existe el modelo de personaje: %s" % ruta)
		return false

	var packed: PackedScene = load(ruta)
	_modelo = packed.instantiate()
	_modelo.scale = Vector3.ONE * ESCALA
	# Los modelos de KayKit miran hacia +Z, pero el juego orienta los cuerpos
	# hacia -Z (el "adelante" de Godot). Sin este giro los personajes andan de
	# espaldas. Se corrige aquí y no en el movimiento para que valga a la vez
	# para el jugador y para el guardia, y sin tocar el cono de visión.
	_modelo.rotation.y = PI
	add_child(_modelo)

	_anim = AnimationPlayer.new()
	_anim.name = "Animador"
	_modelo.add_child(_anim)
	# Las pistas ("Rig_Medium/Skeleton3D:hueso") son relativas a la raíz del
	# modelo, que es el padre de este animador. Hay que fijarlo DESPUÉS de
	# añadirlo al árbol: antes, la ruta no se puede resolver.
	_anim.root_node = NodePath("..")
	_cargar_librerias()
	reproducir(QUIETO)
	return true


func _cargar_librerias() -> void:
	# Un AnimationPlayer recién creado no tiene ninguna librería: hay que añadir
	# la vacía antes de poder meterle animaciones.
	if not _anim.has_animation_library(""):
		_anim.add_animation_library("", AnimationLibrary.new())
	for ruta in LIBRERIAS:
		var packed: PackedScene = load(ruta)
		if packed == null:
			continue
		var temporal := packed.instantiate()
		for hijo in temporal.get_children():
			if hijo is AnimationPlayer:
				var origen := hijo as AnimationPlayer
				for nombre in origen.get_animation_list():
					if not _anim.has_animation(nombre):
						_anim.get_animation_library("").add_animation(
							nombre, origen.get_animation(nombre))
		temporal.queue_free()


## Reproduce una animación con un fundido corto. Ignora la llamada si ya está
## sonando, para no reiniciarla en cada fotograma.
func reproducir(nombre: String, velocidad := 1.0) -> void:
	if _anim == null or nombre == _actual:
		if _anim != null:
			_anim.speed_scale = velocidad
		return
	if not _anim.has_animation(nombre):
		return
	_actual = nombre
	_anim.speed_scale = velocidad
	_anim.play(nombre, FUNDIDO)


## Elige la animación adecuada según lo que esté haciendo el personaje.
func animar_movimiento(velocidad_horizontal: float, corriendo: bool, agachado: bool) -> void:
	if velocidad_horizontal < 0.15:
		reproducir(AGACHADO_QUIETO if agachado else QUIETO)
	elif corriendo:
		reproducir(CORRER)
	else:
		# Agachado reutiliza el caminar, más lento: parece que va con sigilo.
		reproducir(ANDAR, 0.6 if agachado else 1.0)


func animacion_actual() -> String:
	return _actual


## Tinte suave del color de equipo, conservando la textura original del
## personaje. Sirve para reconocer a cada jugador de un vistazo.
func tintar(color: Color, fuerza := 0.45) -> void:
	for malla in _mallas(_modelo):
		var mat := _material_editable(malla)
		if mat != null:
			mat.albedo_color = Color.WHITE.lerp(color, fuerza)


## Semitransparente mientras el jugador está escondido en un mueble.
func hacer_translucido(activo: bool) -> void:
	for malla in _mallas(_modelo):
		var mat := _material_editable(malla)
		if mat == null:
			continue
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if activo else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color.a = 0.35 if activo else 1.0


## Devuelve un material propio de esa malla (copiado del original la primera
## vez), para poder cambiarle color o transparencia sin afectar a los demás
## personajes que comparten el material importado.
func _material_editable(malla: MeshInstance3D) -> StandardMaterial3D:
	if malla.material_override is StandardMaterial3D:
		return malla.material_override
	var original: Material = malla.mesh.surface_get_material(0)
	var mat := StandardMaterial3D.new()
	if original is BaseMaterial3D:
		var base := original as BaseMaterial3D
		mat.albedo_texture = base.albedo_texture
		mat.albedo_color = base.albedo_color
		mat.roughness = base.roughness
		mat.metallic = base.metallic
	malla.material_override = mat
	return mat


func _mallas(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_mallas(c))
	return out


## Postura agachada: no hay animación específica en el pack, así que se baja y
## se inclina un poco el modelo. Con el andar lento da sensación de sigilo.
func agachar(activo: bool) -> void:
	if _modelo == null:
		return
	var destino_y := -0.28 if activo else 0.0
	# Negativo porque el modelo va girado 180 grados: así se inclina hacia
	# delante y no hacia atrás.
	var destino_x := -0.22 if activo else 0.0
	_modelo.position.y = lerpf(_modelo.position.y, destino_y, 0.25)
	_modelo.rotation.x = lerp_angle(_modelo.rotation.x, destino_x, 0.25)
