class_name Interaccion
## Reglas compartidas de interacción entre el cliente y el servidor.
##
## El detector del jugador es una esfera, y una esfera atraviesa los muros: sin
## esta comprobación se podían abrir puertas o coger objetos desde la sala de al
## lado. Se usa en los dos lados: el cliente para no ofrecer el cartel, y el
## servidor —que es quien decide— para no aceptar la orden.

## Distancia máxima a la que el servidor acepta una interacción.
const ALCANCE := 4.0


## ¿Puede el jugador ver el objeto sin que se interponga un muro?
static func hay_linea_de_vision(jugador: Node3D, objetivo: Node3D) -> bool:
	var mundo := jugador.get_world_3d()
	if mundo == null:
		return true
	var desde: Vector3 = jugador.global_position + Vector3.UP * 1.1
	var hasta: Vector3 = objetivo.global_position + Vector3.UP * 0.6

	var consulta := PhysicsRayQueryParameters3D.create(desde, hasta)
	consulta.collision_mask = 1          # solo el mundo sólido
	consulta.collide_with_areas = false
	consulta.exclude = [jugador.get_rid()]

	var golpe := mundo.direct_space_state.intersect_ray(consulta)
	if golpe.is_empty():
		return true
	# Chocar contra el propio objeto es normal: las puertas y las rejas son
	# sólidas, y es justo con lo que queremos interactuar.
	var chocado: Object = golpe.get("collider")
	return chocado is Node and objetivo.is_ancestor_of(chocado as Node)


## Comprobación completa que hace el servidor antes de aceptar una interacción.
static func puede_interactuar(jugador: Node3D, objetivo: Node3D) -> bool:
	if jugador == null or objetivo == null:
		return false
	if jugador.global_position.distance_to(objetivo.global_position) > ALCANCE:
		return false
	return hay_linea_de_vision(jugador, objetivo)
