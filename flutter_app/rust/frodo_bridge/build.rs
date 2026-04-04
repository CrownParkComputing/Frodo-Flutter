/*
 * build.rs — Compiles the Frodo C++ emulator core + FFI wrapper via the `cc` crate.
 *
 * This builds a static archive containing all C++ emulation code plus
 * frodo_ffi.cpp.  The resulting .a / .lib is linked into the Rust cdylib
 * so that Dart FFI can call the extern "C" symbols.
 *
 * SDL2 headers are required.  Set SDL2_INCLUDE_DIR to point at the SDL2
 * include/ directory if it is not in a standard location.
 */

use std::env;
use std::path::PathBuf;

fn main() {
    let flutter_app = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap())
        .join("..") // rust/
        .join(".."); // flutter_app/

    // Frodo core lives in the cebix/frodo4 submodule under its src/ directory.
    let src = flutter_app.join("frodo4").join("src");
    let sdl2_include = flutter_app.join("third_party").join("SDL2").join("include");
    let ffi_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap()).join("cpp");

    // Frodo source files — we use the _SC (sub-cycle) variants, matching the
    // original Android build (FRODO_SC=1).  The non-SC files are excluded.
    let frodo_sources: Vec<PathBuf> = vec![
        src.join("1541d64.cpp"),
        src.join("1541fs.cpp"),
        src.join("1541gcr.cpp"),
        src.join("1541t64.cpp"),
        src.join("C64_SC.cpp"),
        src.join("Cartridge.cpp"),
        src.join("CIA_SC.cpp"),
        src.join("CPU_common.cpp"),
        src.join("CPU1541_SC.cpp"),
        src.join("CPUC64_SC.cpp"),
        src.join("Display.cpp"),
        src.join("IEC.cpp"),
        src.join("main.cpp"),
        src.join("Prefs.cpp"),
        src.join("REU.cpp"),
        src.join("SAM.cpp"),
        src.join("SID.cpp"),
        src.join("Tape.cpp"),
        src.join("VIA_SC.cpp"),
        src.join("VIC_SC.cpp"),
    ];

    let mut build = cc::Build::new();
    build.cpp(true);
    build.std("c++20");

    // Include paths
    build.include(&src);
    build.include(&ffi_dir);       // for sysconfig.h + frodo_ffi.h
    build.include(&sdl2_include);

    // Allow override of SDL2 include path
    if let Ok(sdl2) = env::var("SDL2_INCLUDE_DIR") {
        build.include(&sdl2);
    }

    // Preprocessor defines (must match the CMakeLists.txt)
    build.define("HAVE_SDL", "1");
    build.define("HAVE_CXX20", "1");
    build.define("FRODO_SC", "1");
    build.define("PRECISE_CPU_CYCLES", "1");
    build.define("PRECISE_CIA_CYCLES", "1");
    build.define("FRODO_FLUTTER_HEADLESS", "1");

    // Android-specific when cross compiling
    let target = env::var("TARGET").unwrap_or_default();
    if target.contains("android") {
        build.define("ANDROID", "1");
    }

    // Warnings — the legacy C++ code has some; keep building
    build.flag_if_supported("-Wno-unused-parameter");
    build.flag_if_supported("-Wno-sign-compare");
    build.flag_if_supported("-Wno-deprecated-declarations");

    // Add Frodo source files
    for f in &frodo_sources {
        build.file(f);
    }

    // Add the FFI wrapper
    build.file(ffi_dir.join("frodo_ffi.cpp"));

    build.compile("frodo_core");

    // Tell cargo to re-run if any source changes
    println!("cargo:rerun-if-changed=cpp/frodo_ffi.h");
    println!("cargo:rerun-if-changed=cpp/frodo_ffi.cpp");
    // C64_SC.cpp includes C64.cpp directly; track it explicitly so tape/autostart
    // changes in the shared implementation trigger a native rebuild.
    println!("cargo:rerun-if-changed={}", src.join("C64.cpp").display());
    for f in &frodo_sources {
        println!("cargo:rerun-if-changed={}", f.display());
    }

    println!("cargo:rerun-if-env-changed=SDL2_LIB_DIR");
    if let Ok(sdl2_lib_dir) = env::var("SDL2_LIB_DIR") {
        println!("cargo:rustc-link-search=native={}", sdl2_lib_dir);
    }
    println!("cargo:rustc-link-lib=SDL2");
}
