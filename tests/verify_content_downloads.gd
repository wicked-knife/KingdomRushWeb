extends SceneTree
const Packs = preload("res://scripts/services/content_packs.gd")
var failures: Array[String] = []
var checks := 0
var index: Dictionary
var url := ""
var directory := ""

func _init() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func service(mode: String, cache: String) -> Node:
	var instance := Packs.new()
	check(instance.initialize(index, url + mode + "/", directory.path_join(cache)), "valid test index")
	root.add_child(instance)
	return instance

func _run() -> void:
	create_timer(80.0).timeout.connect(func(): push_error("Download tests timed out"); quit(1))
	var args := OS.get_cmdline_user_args()
	url = args[0]; directory = args[2]
	index = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var packs := service("slow", "normal")
	check(not FileAccess.file_exists("res://pack_probe/a.txt"), "probe is absent before mounting")
	check(await packs.ensure_bundle("a"), "cold HTTP download and mount")
	check(FileAccess.get_file_as_string("res://pack_probe/a.txt").length() == 1024 * 1024, "mounted payload is readable")
	check(packs.network_requests == 1, "one cold transfer")
	check(await packs.ensure_bundle("a") and packs.network_requests == 1, "same-session cache reuse")
	var cached := service("missing", "normal")
	check(await cached.ensure_bundle("a") and cached.network_requests == 0, "disk cache survives service restart")
	cached.queue_free(); await process_frame
	for mode: String in ["missing", "corrupt", "truncated"]:
		var faulty := service(mode, mode)
		check(not await faulty.ensure_bundle("g"), mode + " rejected")
		check(faulty.mounted.is_empty(), mode + " did not mount")
		faulty.base_url = url + "normal/"
		check(await faulty.ensure_bundle("g"), mode + " manual retry succeeds")
		check(DirAccess.get_files_at(faulty.cache_root).size() == 1, mode + " temporary file cleaned")
		faulty.queue_free(); await process_frame
	var b: String = index.bundles.b[0]
	packs.prefetch_bundle("b")
	while packs.network_requests < 2: await process_frame
	await create_timer(0.03).timeout
	check(not packs.mounted.has(b), "prefetch never mounts")
	check(await packs.ensure_bundle("b"), "foreground promotes active prefetch")
	check(packs.network_requests == 2 and packs.mounted.has(b), "promotion retains the same transfer")
	var c: String = index.bundles.c[0]
	packs.prefetch_bundle("c")
	while not packs._jobs.has(c) or packs._jobs[c].status != "ready": await process_frame
	check(not packs.mounted.has(c) and not FileAccess.file_exists("res://pack_probe/c.txt"), "completed prefetch remains unmounted")
	var before: int = packs.network_requests
	check(await packs.ensure_bundle("c") and packs.network_requests == before, "prefetched file mounts without another download")
	var d: String = index.bundles.d[0]
	packs.prefetch_bundle("d")
	while packs._active != d or packs._jobs[d].status != "downloading": await process_frame
	check(await packs.ensure_bundle("e"), "different foreground demand preempts background")
	check(packs._jobs[d].status == "cancelled" and not packs.mounted.has(d), "interrupted background remains unmounted")
	packs.prefetch_bundle("f")
	var f: String = index.bundles.f[0]
	while packs._active != f or packs._jobs[f].status != "downloading": await process_frame
	packs.stop_prefetch()
	await create_timer(0.05).timeout
	check(packs._active == "" and packs._background.is_empty(), "leaving battle cancels background queue")
	check(Array(DirAccess.get_files_at(packs.cache_root)).all(func(name: String): return name.ends_with(".pck")), "cancelled temporary files cleaned")
	check(not await packs.ensure_bundle("unknown"), "unknown bundle is rejected")
	check(not packs.initialize(index, "file:///invalid/", directory.path_join("invalid")), "invalid base URL is rejected")
	packs.queue_free(); await process_frame
	var hashes := {}
	for path: String in ["scripts/services/content_packs.gd", "tests/verify_content_downloads.gd", "tools/check_content_downloads.py"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	var report := {"passed": failures.is_empty(), "checks": checks, "independent_scenarios": 10, "failures": failures, "browser_tested": false, "source_hashes": hashes}
	var file := FileAccess.open("res://reports/content_downloads.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("CONTENT_DOWNLOADS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
