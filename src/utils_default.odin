#+build !wasm32
#+build !wasm64p32

package tiler

import "core:os"
import "core:fmt"
import "core:path/filepath"
import "core:strings"

_read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	return os.read_entire_file(name, allocator, loc)
}

_write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	return os.write_entire_file(name, data, truncate)
}

_list_files_in_dir :: proc(path: string) -> []string {
    f, err := os.open(path)
    defer os.close(f)
    if err != os.ERROR_NONE {
        fmt.eprintln("Could not open directory for reading", err)
        os.exit(1)
    }
    fis: []os.File_Info
    defer os.file_info_slice_delete(fis)
    fis, err = os.read_dir(f, -1) // -1 reads all file infos
    if err != os.ERROR_NONE {
        fmt.eprintln("Could not read directory", err)
        os.exit(2)
    }

    res := make([dynamic]string, context.temp_allocator)

    for fi in fis {
        _, name := filepath.split(fi.fullpath)
        if !fi.is_dir {
            append(&res, strings.clone(name, allocator=context.temp_allocator))
        }
    }

    return res[:]
}
