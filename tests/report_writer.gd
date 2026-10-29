extends RefCounted
## Windows editor/indexer readers can briefly share-lock an existing report.
static func json_file(path: String, value: Variant) -> bool:
	var temporary:=path+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null:push_error("Cannot write report: "+path+" error="+str(FileAccess.get_open_error()));return false
	file.store_string(JSON.stringify(value,"\t"));file.close()
	for attempt in 20:
		var error:=DirAccess.rename_absolute(temporary,path)
		if error==OK:return true
		OS.delay_msec(50)
	push_error("Cannot replace report: "+path);return false
