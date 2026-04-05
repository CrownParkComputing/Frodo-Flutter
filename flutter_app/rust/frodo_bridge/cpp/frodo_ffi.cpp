/*
 * frodo_ffi.cpp — Implements the pure-C API by forwarding to the C++ core.
 * This is almost identical to FrodoJNI.cpp but without JNI types.
 */
#include "frodo_ffi.h"

#include "C64.h"
#include "CIA.h"
#include "SID.h"
#include "1541t64.h"
#include "Cartridge.h"
#include "Display.h"
#include "IEC.h"
#include "Prefs.h"
#include "main.h"

#include <memory>
#include <string>
#include <vector>
#include <filesystem>
#include <fstream>
#include <cstdlib>
#include <ctime>
#include <cctype>
#include <thread>
#include <chrono>
#include <atomic>

#include <SDL.h>

/* ---- internal helpers -------------------------------------------------- */

namespace {
    namespace fs = std::filesystem;
    std::thread g_emu_thread;
    std::atomic<bool> g_emu_running{false};

    bool ready()
    {
        return TheC64 != nullptr && TheC64->TheDisplay != nullptr;
    }

    std::string display_name(const std::string & path)
    {
        fs::path p(path);
        return p.has_filename() ? p.filename().string() : path;
    }

    bool extract_first_archive_entry(const std::string & path)
    {
        std::vector<c64_dir_entry> entries;
        if (!ReadArchDirectory(path, entries) || entries.empty())
            return false;

        const auto & e = entries.front();
        FILE * in = fopen(path.c_str(), "rb");
        if (!in) return false;
        if (fseek(in, (long)e.offset, SEEK_SET) != 0) { fclose(in); return false; }

        std::vector<uint8_t> payload(e.size + 2);
        payload[0] = e.sa_lo;
        payload[1] = e.sa_hi;
        size_t rd = fread(payload.data() + 2, 1, e.size, in);
        fclose(in);
        if (rd != e.size) return false;

        fs::path out_path = fs::path(path).parent_path() / (fs::path(path).stem().string() + "_autostart.prg");
        std::ofstream out(out_path, std::ios::binary | std::ios::trunc);
        if (!out) return false;
        out.write(reinterpret_cast<const char *>(payload.data()), (std::streamsize)payload.size());
        out.close();
        if (!out) return false;

        auto prefs = std::make_unique<Prefs>(ThePrefs);
        prefs->DrivePath[0].clear();
        prefs->TapePath.clear();
        prefs->LoadProgram = out_path.string();
        prefs->AutoStart = true;
        prefs->CartridgePath.clear();
        TheC64->NewPrefs(prefs.get());
        ThePrefs = *prefs;
        TheC64->ShowNotification("Program auto-starting");
        TheC64->ResetAndAutoStart();
        return true;
    }
}

/* ---- C API implementation ---------------------------------------------- */

extern "C" {

static SDL_Scancode sc_from_name(const char * name)
{
    if (!name) return SDL_SCANCODE_UNKNOWN;

    std::string k(name);
    for (char & ch : k) ch = static_cast<char>(std::toupper(static_cast<unsigned char>(ch)));

    if (k == "A") return SDL_SCANCODE_A;
    if (k == "B") return SDL_SCANCODE_B;
    if (k == "C") return SDL_SCANCODE_C;
    if (k == "D") return SDL_SCANCODE_D;
    if (k == "E") return SDL_SCANCODE_E;
    if (k == "F") return SDL_SCANCODE_F;
    if (k == "G") return SDL_SCANCODE_G;
    if (k == "H") return SDL_SCANCODE_H;
    if (k == "I") return SDL_SCANCODE_I;
    if (k == "J") return SDL_SCANCODE_J;
    if (k == "K") return SDL_SCANCODE_K;
    if (k == "L") return SDL_SCANCODE_L;
    if (k == "M") return SDL_SCANCODE_M;
    if (k == "N") return SDL_SCANCODE_N;
    if (k == "O") return SDL_SCANCODE_O;
    if (k == "P") return SDL_SCANCODE_P;
    if (k == "Q") return SDL_SCANCODE_Q;
    if (k == "R") return SDL_SCANCODE_R;
    if (k == "S") return SDL_SCANCODE_S;
    if (k == "T") return SDL_SCANCODE_T;
    if (k == "U") return SDL_SCANCODE_U;
    if (k == "V") return SDL_SCANCODE_V;
    if (k == "W") return SDL_SCANCODE_W;
    if (k == "X") return SDL_SCANCODE_X;
    if (k == "Y") return SDL_SCANCODE_Y;
    if (k == "Z") return SDL_SCANCODE_Z;

    if (k == "0") return SDL_SCANCODE_0;
    if (k == "1") return SDL_SCANCODE_1;
    if (k == "2") return SDL_SCANCODE_2;
    if (k == "3") return SDL_SCANCODE_3;
    if (k == "4") return SDL_SCANCODE_4;
    if (k == "5") return SDL_SCANCODE_5;
    if (k == "6") return SDL_SCANCODE_6;
    if (k == "7") return SDL_SCANCODE_7;
    if (k == "8") return SDL_SCANCODE_8;
    if (k == "9") return SDL_SCANCODE_9;

    if (k == "RETURN" || k == "ENTER") return SDL_SCANCODE_RETURN;
    if (k == "SPACE") return SDL_SCANCODE_SPACE;
    if (k == "ESCAPE" || k == "ESC") return SDL_SCANCODE_ESCAPE;
    if (k == "BACKSPACE") return SDL_SCANCODE_BACKSPACE;
    if (k == "TAB") return SDL_SCANCODE_TAB;

    if (k == "UP") return SDL_SCANCODE_UP;
    if (k == "DOWN") return SDL_SCANCODE_DOWN;
    if (k == "LEFT") return SDL_SCANCODE_LEFT;
    if (k == "RIGHT") return SDL_SCANCODE_RIGHT;

    if (k == "LSHIFT" || k == "SHIFT") return SDL_SCANCODE_LSHIFT;
    if (k == "RSHIFT") return SDL_SCANCODE_RSHIFT;
    if (k == "LCTRL" || k == "RCTRL" || k == "CTRL") return SDL_SCANCODE_LCTRL;
    if (k == "LALT" || k == "RALT" || k == "ALT") return SDL_SCANCODE_LALT;

    if (k == "MINUS") return SDL_SCANCODE_MINUS;
    if (k == "EQUALS" || k == "PLUS") return SDL_SCANCODE_EQUALS;
    if (k == "COMMA") return SDL_SCANCODE_COMMA;
    if (k == "PERIOD") return SDL_SCANCODE_PERIOD;
    if (k == "SLASH") return SDL_SCANCODE_SLASH;
    if (k == "SEMICOLON") return SDL_SCANCODE_SEMICOLON;
    if (k == "APOSTROPHE") return SDL_SCANCODE_APOSTROPHE;
    if (k == "LEFTBRACKET") return SDL_SCANCODE_LEFTBRACKET;
    if (k == "RIGHTBRACKET") return SDL_SCANCODE_RIGHTBRACKET;
    if (k == "BACKSLASH") return SDL_SCANCODE_BACKSLASH;
    if (k == "DELETE") return SDL_SCANCODE_DELETE;
    if (k == "HOME") return SDL_SCANCODE_HOME;

    if (k == "F1") return SDL_SCANCODE_F1;
    if (k == "F2") return SDL_SCANCODE_F2;
    if (k == "F3") return SDL_SCANCODE_F3;
    if (k == "F4") return SDL_SCANCODE_F4;
    if (k == "F5") return SDL_SCANCODE_F5;
    if (k == "F6") return SDL_SCANCODE_F6;
    if (k == "F7") return SDL_SCANCODE_F7;
    if (k == "F8") return SDL_SCANCODE_F8;

    return SDL_SCANCODE_UNKNOWN;
}

int frodo_init(void)
{
    if (g_emu_running.load()) {
        return 0;
    }

    // NOTE: Do NOT include SDL_INIT_JOYSTICK or SDL_INIT_GAMECONTROLLER here.
    // Those subsystems require JVM attachment via SDL_hid_init(), which crashes
    // when called from the Dart FFI thread (JVM pointer is null in that context).
    // We use software joystick overrides (joy_override[]) fed from Android/Dart instead.
    const Uint32 sdlFlags = SDL_INIT_TIMER | SDL_INIT_EVENTS | SDL_INIT_AUDIO;
    if ((SDL_WasInit(sdlFlags) & sdlFlags) != sdlFlags) {
        SDL_SetMainReady();
        if (SDL_InitSubSystem(sdlFlags) < 0) {
            fprintf(stderr, "ERROR: SDL_InitSubSystem failed: %s\n", SDL_GetError());
            return -2;
        }
    }

    // Keep mobile builds audible even if a stale config saved SIDType=NONE.
    if (ThePrefs.SIDType == SIDTYPE_NONE) {
        ThePrefs.SIDType = SIDTYPE_DIGITAL_6581;
    }
    // Prefer software joystick overrides on mobile unless the user explicitly
    // reconfigures ports later.
    ThePrefs.Joystick1Port = 0;
    ThePrefs.Joystick2Port = 0;

    std::srand(std::time(nullptr));
    if (TheApp == nullptr) {
        TheApp = new Frodo();
    }

    if (TheC64 == nullptr) {
        try {
            TheC64 = new C64();
        } catch (...) {
            delete TheApp;
            TheApp = nullptr;
            TheC64 = nullptr;
            return -1;
        }
    }

    try {
        g_emu_running.store(true);
        g_emu_thread = std::thread([]() {
            try {
                if (TheC64) {
                    TheC64->Run();
                }
            } catch (...) {
                // Keep process alive even if emulator initialization fails.
            }
            delete TheC64;
            TheC64 = nullptr;
            g_emu_running.store(false);
        });
    } catch (...) {
        g_emu_running.store(false);
        delete TheC64;
        TheC64 = nullptr;
        delete TheApp;
        TheApp = nullptr;
        return -1;
    }

    return 0;
}

void frodo_shutdown(void)
{
    if (TheC64) {
        TheC64->RequestQuit(0);
    }
    if (g_emu_thread.joinable()) {
        g_emu_thread.join();
    }
    g_emu_running.store(false);

    delete TheC64;
    TheC64 = nullptr;

    delete TheApp;
    TheApp = nullptr;

    SDL_QuitSubSystem(SDL_INIT_TIMER | SDL_INIT_EVENTS | SDL_INIT_AUDIO);
}

int frodo_is_ready(void)
{
    return ready() ? 1 : 0;
}

void frodo_reset(int clear_memory)
{
    if (TheC64) TheC64->Reset(clear_memory != 0);
}

void frodo_reset_and_autostart(void)
{
    if (!TheC64) return;

    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->AutoStart = true;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_nmi(void)
{
    if (TheC64) TheC64->NMI();
}

void frodo_load_file(const char * path)
{
    if (!TheC64 || !path) return;

    try {
        std::string spath(path);
        int type = 0;

        if (IsMountableFile(spath, type)) {
            auto prefs = std::make_unique<Prefs>(ThePrefs);

            if (type == FILE_TAPE_IMAGE) {
                auto cp = std::make_unique<Prefs>(ThePrefs);
                cp->AutoStart = false;
                cp->DrivePath[0].clear();
                cp->TapePath.clear();
                cp->LoadProgram.clear();
                cp->CartridgePath.clear();
                TheC64->SetTapeButtons(TapeState::Stop);
                TheC64->NewPrefs(cp.get());
                ThePrefs = *cp;

                prefs = std::make_unique<Prefs>(ThePrefs);
                prefs->AutoStart = false;
                prefs->DrivePath[0].clear();
                prefs->TapePath = spath;
                prefs->LoadProgram.clear();
                prefs->CartridgePath.clear();
                prefs->ShowLEDs = true;
                TheC64->SetTapeButtons(TapeState::Stop);
                TheC64->NewPrefs(prefs.get());
                ThePrefs = *prefs;
                TheC64->Reset(true);
                TheC64->ShowNotification("Tape mounted: " + display_name(spath));
                return;
            }
            if (type == FILE_DISK_IMAGE || type == FILE_GCR_IMAGE) {
                prefs->AutoStart = false;
                prefs->DrivePath[0] = spath;
                prefs->TapePath.clear();
                prefs->LoadProgram.clear();
                prefs->CartridgePath.clear();
                prefs->Emul1541Proc = true;
                prefs->ShowLEDs = true;
                TheC64->NewPrefs(prefs.get());
                ThePrefs = *prefs;
                TheC64->Reset(true);
                TheC64->ShowNotification("Drive 8 mounted: " + display_name(spath));
                return;
            }
            if (type == FILE_ARCH) {
                std::string lower = spath;
                for (char & ch : lower)
                    ch = (char)tolower((unsigned char)ch);
                if (lower.ends_with(".t64") && extract_first_archive_entry(spath))
                    return;
                prefs->AutoStart = false;
                prefs->DrivePath[0] = spath;
                prefs->TapePath.clear();
                prefs->LoadProgram.clear();
                prefs->CartridgePath.clear();
                prefs->Emul1541Proc = false;
                prefs->ShowLEDs = true;
                TheC64->NewPrefs(prefs.get());
                ThePrefs = *prefs;
                TheC64->Reset(true);
                TheC64->ShowNotification("Archive mounted: " + display_name(spath));
                return;
            }
        }

        if (IsSnapshotFile(spath.c_str())) {
            TheC64->RequestLoadSnapshot(spath);
            return;
        }
        if (IsCartridgeFile(spath)) {
            auto prefs = std::make_unique<Prefs>(ThePrefs);
            prefs->AutoStart = true;
            TheC64->InsertCartridge(spath);
            TheC64->NewPrefs(prefs.get());
            ThePrefs = *prefs;
            TheC64->ResetAndAutoStart();
            return;
        }
        if (IsBASICProgram(spath)) {
            auto prefs = std::make_unique<Prefs>(ThePrefs);
            prefs->LoadProgram = spath;
            prefs->AutoStart = true;
            prefs->CartridgePath.clear();
            TheC64->NewPrefs(prefs.get());
            ThePrefs = *prefs;
            TheC64->ShowNotification("Program auto-starting");
            TheC64->ResetAndAutoStart();
        }
    } catch (const std::exception &e) {
        fprintf(stderr, "ERROR: frodo_load_file exception: %s\n", e.what());
        if (TheC64) {
            TheC64->ShowNotification("Load failed");
        }
    } catch (...) {
        fprintf(stderr, "ERROR: frodo_load_file unknown exception\n");
        if (TheC64) {
            TheC64->ShowNotification("Load failed");
        }
    }
}

int frodo_mount_disk(int drive_number, const char * path)
{
    if (!TheC64 || !path) return 0;

    std::string spath(path);
    int index = drive_number - 8;
    if (index < 0 || index > 3) return 0;

    int type = 0;
    if (!IsMountableFile(spath, type) || type == FILE_TAPE_IMAGE) return 0;

    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->AutoStart = false;
    prefs->DrivePath[index] = spath;
    prefs->ShowLEDs = true;

    if (type == FILE_GCR_IMAGE) {
        if (index != 0) return 0;
        prefs->Emul1541Proc = true;
    } else if (type == FILE_DISK_IMAGE && index == 0) {
        prefs->Emul1541Proc = true;
    } else {
        prefs->Emul1541Proc = false;
    }

    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
    return 1;
}

int frodo_swap_drives(void)
{
    if (!TheC64) return 0;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    std::swap(prefs->DrivePath[0], prefs->DrivePath[1]);
    prefs->AutoStart = false;
    prefs->Emul1541Proc = false;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
    return 1;
}

void frodo_queue_disk_autoload(void)
{
    if (TheC64 && !ThePrefs.DrivePath[0].empty())
        TheC64->AutoStartOp();
}

void frodo_mount_tape(const char * path)
{
    if (!TheC64 || !path) return;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->TapePath = std::string(path);
    prefs->ShowLEDs = true;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_tape_play(void)    { if (TheC64) TheC64->SetTapeButtons(TapeState::Play); }
void frodo_tape_stop(void)    { if (TheC64) TheC64->SetTapeButtons(TapeState::Stop); }
void frodo_tape_record(void)  { if (TheC64) TheC64->SetTapeButtons(TapeState::Record); }
void frodo_tape_rewind(void)  { if (TheC64) TheC64->RewindTape(); }
void frodo_tape_forward(void) { if (TheC64) TheC64->ForwardTape(); }

void frodo_tape_eject(void)
{
    if (TheC64) {
        TheC64->SetTapeButtons(TapeState::Stop);
        TheC64->MountDrive1("");
    }
}

int frodo_tape_position(void)
{
    return TheC64 ? TheC64->TapePosition() : 0;
}

int frodo_tape_button_state(void)
{
    return TheC64 ? (int)TheC64->TapeButtonState() : 0;
}

int frodo_tape_drive_state(void)
{
    return TheC64 ? (int)TheC64->TapeDriveState() : 0;
}

void frodo_tape_set_speed(int multiplier)
{
    if (!TheC64) return;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->LimitSpeed = (multiplier <= 1);
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_insert_cartridge(const char * path)
{
    if (TheC64 && path) TheC64->InsertCartridge(std::string(path));
}

static void inject_key(SDL_Scancode sc, bool key_up)
{
    SDL_Event e;
    memset(&e, 0, sizeof(e));
    e.type = key_up ? SDL_KEYUP : SDL_KEYDOWN;
    e.key.state = key_up ? SDL_RELEASED : SDL_PRESSED;
    e.key.keysym.scancode = sc;
    e.key.keysym.sym = SDL_GetKeyFromScancode(sc);
    SDL_PushEvent(&e);
}

void frodo_key_down(const char * name)
{
    SDL_Scancode sc = sc_from_name(name);
    if (sc != SDL_SCANCODE_UNKNOWN)
        inject_key(sc, false);
}

void frodo_key_up(const char * name)
{
    SDL_Scancode sc = sc_from_name(name);
    if (sc != SDL_SCANCODE_UNKNOWN)
        inject_key(sc, true);
}

void frodo_key_combo(const char * mod_name, const char * key_name)
{
    SDL_Scancode mod = sc_from_name(mod_name);
    SDL_Scancode key = sc_from_name(key_name);
    if (mod == SDL_SCANCODE_UNKNOWN || key == SDL_SCANCODE_UNKNOWN) return;
    inject_key(mod, false);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    inject_key(key, false);
    inject_key(key, true);
    inject_key(mod, true);
}

void frodo_set_joystick_ports(int port1, int port2)
{
    if (!TheC64) return;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->Joystick1Port = port1;
    prefs->Joystick2Port = port2;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_toggle_joystick_swap(void)
{
    if (!TheC64) return;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->JoystickSwap = !ThePrefs.JoystickSwap;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_joystick_set_override(int port, int bits)
{
    if (!TheC64 || !TheC64->TheCIA1) return;
    uint8_t val = (uint8_t)bits;
    if (port == 1)
        TheC64->TheCIA1->Joystick1 = val;
    else if (port == 2)
        TheC64->TheCIA1->Joystick2 = val;
}

void frodo_capture_frame(uint32_t * out_argb)
{
    if (!ready() || !out_argb) return;

    // Pepto palette (default)
    static const uint32_t palette_pepto[16] = {
        0x000000, 0xffffff, 0x860119, 0x4cc1e3,
        0x8817bd, 0x35ac0a, 0x2007c0, 0xcff22d,
        0x883e00, 0x402a00, 0xcb5537, 0x343434,
        0x686868, 0x8bff59, 0x6845ff, 0xa1a1a1
    };
    // Colodore palette
    static const uint32_t palette_colodore[16] = {
        0x000000, 0xffffff, 0x813338, 0x75cec8,
        0x8e3c97, 0x56ac4d, 0x2e2c9b, 0xedf171,
        0x8e5029, 0x553800, 0xc46c71, 0x4a4a4a,
        0x7b7b7b, 0xa9ff9f, 0x706deb, 0xb2b2b2
    };
    // UI extra palette entries (indices 16-21)
    static const uint32_t palette_ui[6] = {
        0xd0d0d0, // fill_gray (16)
        0xf0f0f0, // shine_gray (17)
        0x404040, // shadow_gray (18)
        0xf00000, // red (19)
        0x300000, // dark_red (20)
        0x00c000  // green (21)
    };

    const uint32_t * c64_pal = (ThePrefs.Palette == PALETTE_COLODORE)
        ? palette_colodore : palette_pepto;

    const uint8_t * src = TheC64->TheDisplay->BitmapBase();
    const unsigned total = DISPLAY_X * DISPLAY_Y;
    constexpr unsigned PALETTE_UI_END = 22; // indices 16-21 are UI overlay colors
    for (unsigned i = 0; i < total; ++i) {
        uint8_t idx = src[i];
        uint32_t rgb;
        if (idx < 16)
            rgb = c64_pal[idx];
        else if (idx < PALETTE_UI_END)
            rgb = palette_ui[idx - 16];
        else
            rgb = 0;
        out_argb[i] = 0xff000000u | rgb;
    }
}

void frodo_pause_audio(void)
{
    if (TheC64 && TheC64->TheSID) TheC64->TheSID->PauseSound();
}

void frodo_resume_audio(void)
{
    if (TheC64 && TheC64->TheSID) TheC64->TheSID->ResumeSound();
}

void frodo_autostart_mounted_media(void)
{
    if (!TheC64) return;
    if (ThePrefs.DrivePath[0].empty() && ThePrefs.TapePath.empty()) return;
    auto prefs = std::make_unique<Prefs>(ThePrefs);
    prefs->AutoStart = true;
    TheC64->NewPrefs(prefs.get());
    ThePrefs = *prefs;
}

void frodo_start_current_media(void)
{
    if (!TheC64) return;
    if (ThePrefs.DrivePath[0].empty() && ThePrefs.TapePath.empty()) return;
    TheC64->AutoStartOp();
}

void frodo_queue_tape_autoload(void)
{
    if (TheC64 && !ThePrefs.TapePath.empty())
        TheC64->AutoStartOp();
}

} /* extern "C" */
