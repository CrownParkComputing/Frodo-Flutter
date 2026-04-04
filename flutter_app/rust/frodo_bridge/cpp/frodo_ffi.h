/*
 * frodo_ffi.h — Pure-C API wrapping the Frodo C++ emulator core.
 * Called from Rust via FFI, which is in turn called from Flutter/Dart.
 */
#ifndef FRODO_FFI_H
#define FRODO_FFI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Lifecycle */
int      frodo_init(void);
void     frodo_shutdown(void);
int      frodo_is_ready(void);

/* Reset / NMI */
void     frodo_reset(int clear_memory);
void     frodo_reset_and_autostart(void);
void     frodo_nmi(void);

/* File loading — the mega-dispatcher */
void     frodo_load_file(const char * path);

/* Disk drive */
int      frodo_mount_disk(int drive_number, const char * path);
int      frodo_swap_drives(void);
void     frodo_queue_disk_autoload(void);

/* Tape */
void     frodo_mount_tape(const char * path);
void     frodo_tape_play(void);
void     frodo_tape_stop(void);
void     frodo_tape_record(void);
void     frodo_tape_rewind(void);
void     frodo_tape_forward(void);
void     frodo_tape_eject(void);
int      frodo_tape_position(void);
int      frodo_tape_button_state(void);
int      frodo_tape_drive_state(void);
void     frodo_tape_set_speed(int multiplier);

/* Cartridge */
void     frodo_insert_cartridge(const char * path);

/* Input — key injection by SDL scancode name */
void     frodo_key_down(const char * scancode_name);
void     frodo_key_up(const char * scancode_name);
void     frodo_key_combo(const char * mod_name, const char * key_name);

/* Joystick */
void     frodo_set_joystick_ports(int port1, int port2);
void     frodo_toggle_joystick_swap(void);
void     frodo_joystick_set_override(int port, int bits);  /* Android software joystick: bits = CIA mask (0xff=none) */

/* Display — copy ARGB framebuffer */
#define  FRODO_DISPLAY_W  0x180   /* 384 */
#define  FRODO_DISPLAY_H  0x110   /* 272 */
void     frodo_capture_frame(uint32_t * out_argb);

/* Audio pause / resume (for app lifecycle) */
void     frodo_pause_audio(void);
void     frodo_resume_audio(void);

/* Auto-start helpers */
void     frodo_autostart_mounted_media(void);
void     frodo_start_current_media(void);
void     frodo_queue_tape_autoload(void);

#ifdef __cplusplus
}
#endif

#endif /* FRODO_FFI_H */
