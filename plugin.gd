@tool
extends EditorPlugin

var dock: Control
var dockBtn : Button
var projectSelect: OptionButton
var dirline: LineEdit
var fileline: LineEdit
var progressBar: ProgressBar
var progressLabel: Label
var currentLabel: Label
var detectedProjects: Array[String]
var compiledRemaps: Dictionary

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	
	var inputBox = HBoxContainer.new()
	dock.add_child(inputBox)
	
	var projectScanBtn = Button.new()
	projectScanBtn.text = "Scan"
	projectScanBtn.pressed.connect(func(): scanProjects())
	inputBox.add_child(projectScanBtn)

	projectSelect = OptionButton.new()
	projectSelect.item_selected.connect(func(index: int):
		dirline.text = detectedProjects[index]
		fileline.text = detectedProjects[index].get_file() + ".zip"
		)
	inputBox.add_child(projectSelect)

	dirline = LineEdit.new()
	dirline.placeholder_text = "res://mods/MyMod"
	dirline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inputBox.add_child(dirline)

	var fileDialogBtn = Button.new()
	fileDialogBtn.text = "..."
	fileDialogBtn.pressed.connect(func(): 
		var fd = FileDialog.new()
		fd.size = Vector2(700,400)
		fd.title = "Select mod folder"
		fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		fd.access = FileDialog.ACCESS_RESOURCES
		fd.dir_selected.connect(func(dir): dirline.text = dir)
		fd.canceled.connect(func(): fd.queue_free())
		fd.close_requested.connect(func(): fd.queue_free())
		
		add_child(fd)
		fd.popup_centered()
		)
	inputBox.add_child(fileDialogBtn)

	fileline = LineEdit.new()
	fileline.placeholder_text = "mod.zip"
	fileline.custom_minimum_size = Vector2(200, 0)
	inputBox.add_child(fileline)

	var btn = Button.new()
	btn.text = "Export!"
	btn.custom_minimum_size = Vector2(100, 0)
	btn.pressed.connect(exportZip)
	inputBox.add_child(btn)

	var progressBox = HBoxContainer.new()
	dock.add_child(progressBox)

	progressBar = ProgressBar.new()
	progressBar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progressBox.add_child(progressBar)

	progressLabel = Label.new()
	progressLabel.custom_minimum_size = Vector2(100, 0)
	progressBox.add_child(progressLabel)

	currentLabel = Label.new()
	currentLabel.text = "Select mod folder, enter zip name and press Export!"
	dock.add_child(currentLabel)
	
	scanProjects()
	
	dockBtn = add_control_to_bottom_panel(dock, "Mod")

func scanProjects():
	projectSelect.clear()
	detectedProjects.clear()

	scanDirForProjects("res://")

	if projectSelect.item_count > 0:
		projectSelect.item_selected.emit(0)
	
func scanDirForProjects(dir):
	for d in DirAccess.get_directories_at(dir):
		if FileAccess.file_exists(dir.path_join(d).path_join("mod.txt")):
			detectedProjects.append(dir.path_join(d))
			projectSelect.add_item(d)
		else:
			scanDirForProjects(dir.path_join(d))

var zipPaths = []
var customResourceHash = ""
var files: Array[String] = []
func exportZip():
	currentLabel.modulate = Color.WHITE
	compiledRemaps = {}

	var dir = dirline.text
	var out = fileline.text

	var modCfgPath = null
	var overrideCfgPath = dir.path_join("override.cfg")
	if FileAccess.file_exists(dir.path_join("mod.txt")):
		modCfgPath = dir.path_join("mod.txt")

	customResourceHash = DirAccess.get_directories_at("res://.godot/exported")[0]
	files = []
	collectFiles(dir)

	zipPaths = []
	var zip = ZIPPacker.new()
	zip.open("res://mods/" + out)
	
	var i = 1
	for f in files:
		currentLabel.text = "Exporting " + f + "..."
		progressLabel.text = str(i) + "/" + str(files.size())
		progressBar.min_value = 0
		progressBar.step = 1
		progressBar.max_value = files.size()
		progressBar.value = i
		await get_tree().create_timer(0.01).timeout
		
		if f == overrideCfgPath:
			zipAddFile(zip, f, "override.cfg")
		elif f != modCfgPath:
			addFile(zip, f)
			
		i += 1
	
	if modCfgPath:
		var modcfg = ConfigFile.new()
		modcfg.load(modCfgPath)

		# Store the remaps defined in the mod.txt override section
		for src in modcfg.get_section_keys("override"):
			var remapCfg = ConfigFile.new()
			var override = modcfg.get_value("override", src)
			override = compiledRemaps.get(override, override)
			remapCfg.set_value("remap", "path", override)
			zipAddBuf(zip, src + ".remap", remapCfg.encode_to_text().to_utf8_buffer())
		
		# Remove the override section
		modcfg.erase_section("override")
		# Store the mod.txt
		zipAddBuf(zip, "mod.txt", modcfg.encode_to_text().to_utf8_buffer())
	
	zip.close()
	currentLabel.text = "Done!"
	currentLabel.modulate = Color.LIME
	OS.shell_show_in_file_manager(ProjectSettings.globalize_path("res://mods/" + out))

func collectFiles(dir: String):
	for d in DirAccess.get_directories_at(dir):
		if not d.ends_with(".git"):
			collectFiles(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		if dir.ends_with(".import"): continue
		files.append(dir.path_join(f))

func addFile(zip: ZIPPacker, path: String):
	var f: String = path.get_file()
	var dir: String = path.trim_suffix(f)

	var importPath = dir.path_join(f + ".import")
	if FileAccess.file_exists(importPath):
		var fa = FileAccess.open(importPath, FileAccess.ModeFlags.READ)
		var importCfg = ConfigFile.new()
		importCfg.parse(fa.get_as_text())
		fa.close()

		# Store dest files
		if importCfg.has_section_key("deps", "dest_files"):
			for df in importCfg.get_value("deps", "dest_files"):
				zipAddFile(zip, df)

		# Store the .import file 
		var remapCfg = ConfigFile.new()
		for k in importCfg.get_section_keys("remap"):
			if k == "generator_parameters": continue
			remapCfg.set_value("remap", k, importCfg.get_value("remap", k))
		zipAddBuf(zip, dir.path_join(f + ".import"), remapCfg.encode_to_text().to_utf8_buffer())
	else:
		# Convert text resources to binary
		if f.ends_with(".tres") || f.ends_with(".tscn"):
			# Convert to binary and store
			var binaryName = f.trim_suffix(".tres").trim_suffix(".tscn") + (".scn" if f.ends_with(".tscn") else ".res")
			var res: Resource = ResourceLoader.load(dir.path_join(f))
			var binOut = "res://.godot/exported".path_join(customResourceHash) \
				.path_join("export-" + dir.path_join(f).md5_text() + "-" + binaryName);
			ResourceSaver.save(res, binOut)
			zipAddFile(zip, binOut)

			# Save remap
			var remapCfg = ConfigFile.new()
			remapCfg.set_value("remap", "path", binOut)
			compiledRemaps[path] = binOut
			zipAddBuf(zip, dir.path_join(f + ".remap"), remapCfg.encode_to_text().to_utf8_buffer())
		else:
			# Store the file raw
			zipAddFile(zip, dir.path_join(f))

func zipAddBuf(zip: ZIPPacker, path: String, buf: PackedByteArray):
	path = path.trim_prefix("res://")
	if path in zipPaths:
		return
		
	zip.start_file(path)
	zip.write_file(buf)
	zip.close_file()

	zipPaths.append(path)

func zipAddFile(zip: ZIPPacker, path: String, dest: String = ""):
	path = path.trim_prefix("res://")
	if path in zipPaths:
		return

	if dest == "":
		dest = path

	zip.start_file(dest)
	var fa = FileAccess.open("res://" + path, FileAccess.ModeFlags.READ)
	zip.write_file(fa.get_buffer(fa.get_length()))
	fa.close()
	zip.close_file()

	zipPaths.append(path)

func _exit_tree() -> void:
	remove_control_from_bottom_panel(dock)
	dock.queue_free()
