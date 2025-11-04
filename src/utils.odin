// Wraps os.read_entire_file and os.write_entire_file, but they also work with emscripten.

package tiler

@(require_results)
read_entire_file :: proc(
    name: string,
    allocator := context.allocator,
    loc := #caller_location,
) -> (
    data: []byte,
    success: bool,
) {
    return _read_entire_file(name, allocator, loc)
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
    return _write_entire_file(name, data, truncate)
}

list_files_in_dir :: proc(path: string, allocator := context.temp_allocator) -> [dynamic]string {
    return _list_files_in_dir(path, allocator)
}
