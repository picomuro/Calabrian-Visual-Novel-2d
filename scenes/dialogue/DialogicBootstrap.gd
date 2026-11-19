class_name DialogicBootstrap
extends RefCounted
## DialogicBootstrap — garantisce che Dialogic trovi personaggi e timeline.
##
## Dialogic risolve i nomi usati nelle timeline ("Padre: ...", "join Tu left")
## tramite gli elenchi dialogic/directories/* in project.godot. Al primo import di
## una copia pulita del progetto (clone da git, altro PC, build da zero) l'editor
## li svuota: senza questo controllo i dialoghi Dialogic partirebbero senza
## personaggi né nomi. Qui gli elenchi vengono completati a runtime leggendo le
## cartelle dei dati (identificatore = nome del file, come fa l'editor).
##
## Nota per le build da zero: aprire/importare il progetto due volte prima di
## esportare ripristina anche gli elenchi in project.godot.


const CHARACTERS_DIR: String = "res://data/dialogic/characters/"
const TIMELINES_DIR: String = "res://data/dialogic/timelines/"


## Da chiamare prima di Dialogic.start().
static func ensure_directories() -> void:
	_ensure_directory("dch", CHARACTERS_DIR)
	_ensure_directory("dtl", TIMELINES_DIR)


static func _ensure_directory(extension: String, folder: String) -> void:
	var directory: Dictionary = DialogicResourceUtil.get_directory(extension).duplicate()
	var added: PackedStringArray = []
	for path: String in _list_resources(folder, extension):
		var identifier: String = path.get_file().get_basename()
		if not directory.has(identifier):
			directory[identifier] = path
			added.append(identifier)
	if added.is_empty():
		return
	push_warning("DialogicBootstrap: elenco '%s' incompleto in project.godot, completato a runtime con: %s." % [extension, ", ".join(added)])
	DialogicResourceUtil.set_directory(extension, directory)


## File con l'estensione indicata dentro [param folder]. Nei giochi esportati alcuni
## file possono comparire come "<nome>.remap": il suffisso viene rimosso.
static func _list_resources(folder: String, extension: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for file_name: String in DirAccess.get_files_at(folder):
		var clean_name: String = file_name.trim_suffix(".remap")
		if clean_name.get_extension() == extension:
			result.append(folder.path_join(clean_name))
	return result
