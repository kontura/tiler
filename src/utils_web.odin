// Implementations of `read_entire_file` and `write_entire_file` using the libc
// stuff emscripten exposes. You can read the files that get bundled by
// `--preload-file assets` in `build_web` script.

#+build wasm32, wasm64p32

package tiler

import "base:runtime"
import "core:log"
import "core:c"
import "core:strings"

// These will be linked in by emscripten.
@(default_calling_convention = "c")
foreign {
	fopen   :: proc(filename, mode: cstring) -> ^FILE ---
	opendir :: proc(filename: cstring) -> ^DIR ---
        readdir :: proc(dirp: ^DIR) -> ^dirent ---
	fseek   :: proc(stream: ^FILE, offset: c.long, whence: Whence) -> c.int ---
	ftell   :: proc(stream: ^FILE) -> c.long ---
	fclose  :: proc(stream: ^FILE) -> c.int ---
	fread   :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: ^FILE) -> c.size_t ---
	fwrite  :: proc(ptr: rawptr, size: c.size_t, nmemb: c.size_t, stream: ^FILE) -> c.size_t ---
}

@(private="file")
FILE :: struct {}

@(private="file")
DIR :: struct {}

@(private="file")
dirent :: struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]c.char,
}

Whence :: enum c.int {
	SET,
	CUR,
	END,
}

_list_files_in_dir :: proc(path: string) -> []string {
    data := make([dynamic]string, context.temp_allocator)
    d := opendir(strings.clone_to_cstring(path, context.temp_allocator))
    if d != nil {
        dir := readdir(d)
        for dir != nil {
            // type 8 should be regular file
            if dir != nil && dir.d_type == 8 {
                str := ([^]u8)(&dir.d_name)
                str_size := int(dir.d_reclen) - 1 - cast(int)offset_of(dirent, d_name)
                for str[str_size] != 0 {
                    str_size -= 1
                }
                for str[str_size-1] == 0 {
                    str_size -= 1
                }
                append(&data, string(str[:str_size]))
            }
            dir = readdir(d)
        }
    }

    return data[:]
}

// Similar to raylib's LoadFileData
_read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := fopen(strings.clone_to_cstring(name, context.temp_allocator), "rb")

	if file == nil {
		log.errorf("Failed to open file %v", name)
		return
	}

	defer fclose(file)

	fseek(file, 0, .END)
	size := ftell(file)
	fseek(file, 0, .SET)

	if size <= 0 {
		log.errorf("Failed to read file %v", name)
		return
	}

	data_err: runtime.Allocator_Error
	data, data_err = make([]byte, size, allocator, loc)

	if data_err != nil {
		log.errorf("Error allocating memory: %v", data_err)
		return
	}

	read_size := fread(raw_data(data), 1, c.size_t(size), file)

	if read_size != c.size_t(size) {
		log.warnf("File %v partially loaded (%i bytes out of %i)", name, read_size, size)
	}

	log.debugf("Successfully loaded %v", name)
	return data, true
}

// Similar to raylib's SaveFileData.
//
// Note: This can save during the current session, but I don't think you can
// save any data between sessions. So when you close the tab your saved files
// are gone. Perhaps you could communicate back to emscripten and save a cookie.
// Or communicate with a server and tell it to save data.
_write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	if name == "" {
		log.error("No file name provided")
		return
	}

	file := fopen(strings.clone_to_cstring(name, context.temp_allocator), truncate ? "wb" : "ab")
	defer fclose(file)

	if file == nil {
		log.errorf("Failed to open '%v' for writing", name)
		return
	}

	bytes_written := fwrite(raw_data(data), 1, len(data), file)

	if bytes_written == 0 {
		log.errorf("Failed to write file %v", name)
		return
	} else if bytes_written != len(data) {
		log.errorf("File partially written, wrote %v out of %v bytes", bytes_written, len(data))
		return
	}

	log.debugf("File written successfully: %v", name)
	return true
}
