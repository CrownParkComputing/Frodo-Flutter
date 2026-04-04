//! Rust FFI bridge for the Frodo C64 emulator core.
//!
//! This crate exposes safe(r) Rust wrappers around the C functions defined
//! in `frodo_ffi.h` / `frodo_ffi.cpp`.  Dart's FFI layer calls the
//! `#[no_mangle] extern "C"` symbols exported here.

#![allow(non_camel_case_types)]

use std::ffi::CString;
use std::sync::atomic::{AtomicBool, Ordering};

/// Display dimensions (must match frodo_ffi.h)
pub const DISPLAY_W: u32 = 384;
pub const DISPLAY_H: u32 = 272;
pub const FRAME_BYTES: usize = (DISPLAY_W * DISPLAY_H * 4) as usize;

static INITIALIZED: AtomicBool = AtomicBool::new(false);

// ---------------------------------------------------------------------------
// Raw C bindings (private)
// ---------------------------------------------------------------------------
mod ffi {
    extern "C" {
        pub fn frodo_init() -> i32;
        pub fn frodo_shutdown();
        pub fn frodo_is_ready() -> i32;

        pub fn frodo_reset(clear_memory: i32);
        pub fn frodo_reset_and_autostart();
        pub fn frodo_nmi();

        pub fn frodo_load_file(path: *const std::ffi::c_char);
        pub fn frodo_mount_disk(drive_number: i32, path: *const std::ffi::c_char) -> i32;
        pub fn frodo_swap_drives() -> i32;
        pub fn frodo_queue_disk_autoload();

        pub fn frodo_mount_tape(path: *const std::ffi::c_char);
        pub fn frodo_tape_play();
        pub fn frodo_tape_stop();
        pub fn frodo_tape_record();
        pub fn frodo_tape_rewind();
        pub fn frodo_tape_forward();
        pub fn frodo_tape_eject();
        pub fn frodo_tape_position() -> i32;
        pub fn frodo_tape_button_state() -> i32;
        pub fn frodo_tape_drive_state() -> i32;
        pub fn frodo_tape_set_speed(multiplier: i32);

        pub fn frodo_insert_cartridge(path: *const std::ffi::c_char);

        pub fn frodo_key_down(name: *const std::ffi::c_char);
        pub fn frodo_key_up(name: *const std::ffi::c_char);
        pub fn frodo_key_combo(
            mod_name: *const std::ffi::c_char,
            key_name: *const std::ffi::c_char,
        );

        pub fn frodo_set_joystick_ports(port1: i32, port2: i32);
        pub fn frodo_toggle_joystick_swap();
        pub fn frodo_joystick_set_override(port: i32, bits: i32);

        pub fn frodo_capture_frame(out_argb: *mut u32);

        pub fn frodo_pause_audio();
        pub fn frodo_resume_audio();
        pub fn frodo_autostart_mounted_media();
        pub fn frodo_start_current_media();
        pub fn frodo_queue_tape_autoload();
    }
}

// ---------------------------------------------------------------------------
// Safe public API — these are the symbols Dart calls via FFI
// ---------------------------------------------------------------------------

fn _to_c(s: &str) -> Option<CString> {
    CString::new(s).ok()
}

/// Initialize the emulator. Returns 0 on success, negative on error.
#[no_mangle]
pub extern "C" fn bridge_init() -> i32 {
    if INITIALIZED.load(Ordering::SeqCst) {
        return 0;
    }
    let rc = unsafe { ffi::frodo_init() };
    if rc >= 0 {
        INITIALIZED.store(true, Ordering::SeqCst);
    }
    rc
}

/// Shut down the emulator and release resources.
#[no_mangle]
pub extern "C" fn bridge_shutdown() {
    if INITIALIZED.swap(false, Ordering::SeqCst) {
        unsafe { ffi::frodo_shutdown() };
    }
}

#[no_mangle]
pub extern "C" fn bridge_is_ready() -> i32 {
    unsafe { ffi::frodo_is_ready() }
}

#[no_mangle]
pub extern "C" fn bridge_reset(clear_memory: i32) {
    unsafe { ffi::frodo_reset(clear_memory) };
}

#[no_mangle]
pub extern "C" fn bridge_reset_and_autostart() {
    unsafe { ffi::frodo_reset_and_autostart() };
}

#[no_mangle]
pub extern "C" fn bridge_nmi() {
    unsafe { ffi::frodo_nmi() };
}

/// Load a file (D64, T64, TAP, PRG, CRT, snapshot, etc.)
/// `path` must be a null-terminated UTF-8 string.
#[no_mangle]
pub extern "C" fn bridge_load_file(path: *const std::ffi::c_char) {
    if path.is_null() {
        return;
    }
    unsafe { ffi::frodo_load_file(path) };
}

#[no_mangle]
pub extern "C" fn bridge_mount_disk(drive_number: i32, path: *const std::ffi::c_char) -> i32 {
    if path.is_null() {
        return 0;
    }
    unsafe { ffi::frodo_mount_disk(drive_number, path) }
}

#[no_mangle]
pub extern "C" fn bridge_swap_drives() -> i32 {
    unsafe { ffi::frodo_swap_drives() }
}

#[no_mangle]
pub extern "C" fn bridge_queue_disk_autoload() {
    unsafe { ffi::frodo_queue_disk_autoload() };
}

#[no_mangle]
pub extern "C" fn bridge_mount_tape(path: *const std::ffi::c_char) {
    if path.is_null() {
        return;
    }
    unsafe { ffi::frodo_mount_tape(path) };
}

#[no_mangle]
pub extern "C" fn bridge_tape_play() {
    unsafe { ffi::frodo_tape_play() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_stop() {
    unsafe { ffi::frodo_tape_stop() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_record() {
    unsafe { ffi::frodo_tape_record() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_rewind() {
    unsafe { ffi::frodo_tape_rewind() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_forward() {
    unsafe { ffi::frodo_tape_forward() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_eject() {
    unsafe { ffi::frodo_tape_eject() };
}

#[no_mangle]
pub extern "C" fn bridge_tape_position() -> i32 {
    unsafe { ffi::frodo_tape_position() }
}

#[no_mangle]
pub extern "C" fn bridge_tape_button_state() -> i32 {
    unsafe { ffi::frodo_tape_button_state() }
}

#[no_mangle]
pub extern "C" fn bridge_tape_drive_state() -> i32 {
    unsafe { ffi::frodo_tape_drive_state() }
}

#[no_mangle]
pub extern "C" fn bridge_tape_set_speed(multiplier: i32) {
    unsafe { ffi::frodo_tape_set_speed(multiplier) };
}

#[no_mangle]
pub extern "C" fn bridge_insert_cartridge(path: *const std::ffi::c_char) {
    if path.is_null() {
        return;
    }
    unsafe { ffi::frodo_insert_cartridge(path) };
}

#[no_mangle]
pub extern "C" fn bridge_key_down(name: *const std::ffi::c_char) {
    if name.is_null() {
        return;
    }
    unsafe { ffi::frodo_key_down(name) };
}

#[no_mangle]
pub extern "C" fn bridge_key_up(name: *const std::ffi::c_char) {
    if name.is_null() {
        return;
    }
    unsafe { ffi::frodo_key_up(name) };
}

#[no_mangle]
pub extern "C" fn bridge_key_combo(
    mod_name: *const std::ffi::c_char,
    key_name: *const std::ffi::c_char,
) {
    if mod_name.is_null() || key_name.is_null() {
        return;
    }
    unsafe { ffi::frodo_key_combo(mod_name, key_name) };
}

#[no_mangle]
pub extern "C" fn bridge_set_joystick_ports(port1: i32, port2: i32) {
    unsafe { ffi::frodo_set_joystick_ports(port1, port2) };
}

#[no_mangle]
pub extern "C" fn bridge_toggle_joystick_swap() {
    unsafe { ffi::frodo_toggle_joystick_swap() };
}

/// Set software joystick state for a port (used on Android when no SDL controller is open).
/// `bits` is the CIA joystick mask: 0xff = nothing, clear bit to activate direction/fire.
/// Bit layout: bit0=Up, bit1=Down, bit2=Left, bit3=Right, bit4=Fire.
#[no_mangle]
pub extern "C" fn bridge_joystick_set_override(port: i32, bits: i32) {
    unsafe { ffi::frodo_joystick_set_override(port, bits) };
}

/// Copy the current frame into `out_argb`.  The caller must provide a buffer
/// of at least `DISPLAY_W * DISPLAY_H` u32 elements (ARGB8888).
#[no_mangle]
pub extern "C" fn bridge_capture_frame(out_argb: *mut u32) {
    if out_argb.is_null() {
        return;
    }
    unsafe { ffi::frodo_capture_frame(out_argb) };
}

#[no_mangle]
pub extern "C" fn bridge_pause_audio() {
    unsafe { ffi::frodo_pause_audio() };
}

#[no_mangle]
pub extern "C" fn bridge_resume_audio() {
    unsafe { ffi::frodo_resume_audio() };
}

#[no_mangle]
pub extern "C" fn bridge_autostart_mounted_media() {
    unsafe { ffi::frodo_autostart_mounted_media() };
}

#[no_mangle]
pub extern "C" fn bridge_start_current_media() {
    unsafe { ffi::frodo_start_current_media() };
}

#[no_mangle]
pub extern "C" fn bridge_queue_tape_autoload() {
    unsafe { ffi::frodo_queue_tape_autoload() };
}

/// Convenience: returns display width.
#[no_mangle]
pub extern "C" fn bridge_display_width() -> u32 {
    DISPLAY_W
}

/// Convenience: returns display height.
#[no_mangle]
pub extern "C" fn bridge_display_height() -> u32 {
    DISPLAY_H
}
