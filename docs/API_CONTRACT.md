# Core API Contract & FFI Specification: CustomDAW

## 1. Design Principles for the C-ABI Boundary

1. **Flat, C-Compatible Declarations:** All exports use `extern "C"` with `#[no_mangle]` and `#[repr(C)]` structs. No C++ name-mangling, no Rust trait objects, and no managed references cross the boundary.
2. **Opaque Engine Handle:** The engine instance is held behind an opaque pointer `*mut DAWEngine`. The UI runtime treats this as an `IntPtr` and never dereferences it directly.
3. **Explicit Ownership & Lifetimes:** Any memory allocated by Rust must be deallocated by Rust via an explicit destructor function (e.g., `daw_engine_destroy()`).
4. **Command & Query Asynchrony:** Control operations return immediately. State is queried or polled asynchronously via the telemetry queue.
5. **Deterministic Error Codes:** Functions return integer error codes (`DAWResult`), never raw exceptions or panics.

---

## 2. Status & Error Codes (`DAWResult`)

```c
typedef enum DAWResult {
    DAW_OK                      = 0,
    DAW_ERR_INVALID_HANDLE      = -1,
    DAW_ERR_DEVICE_INIT_FAILED  = -2,
    DAW_ERR_STREAM_ACTIVE       = -3,
    DAW_ERR_STREAM_STOPPED      = -4,
    DAW_ERR_QUEUE_FULL          = -5,
    DAW_ERR_INVALID_PARAMETER   = -6,
    DAW_ERR_FILE_NOT_FOUND      = -7,
    DAW_ERR_UNSUPPORTED_FORMAT  = -8,
    DAW_ERR_UNKNOWN             = -99
} DAWResult;
```

---

## 3. Data Structures (`#[repr(C)]`)

### 3.1 Device Information
```c
typedef struct DAWDeviceInfo {
    int32_t id;
    char name[256];
    uint32_t default_sample_rate;
    uint32_t min_channels;
    uint32_t max_channels;
    uint8_t is_default;
} DAWDeviceInfo;
```

### 3.2 Engine Configuration
```c
typedef struct DAWConfig {
    int32_t output_device_id;   // -1 for system default
    uint32_t sample_rate;       // e.g., 44100, 48000
    uint32_t buffer_size_frames;// e.g., 128, 256, 512
} DAWConfig;
```

### 3.3 Engine Commands
```c
typedef enum DAWCommandType {
    DAW_CMD_PLAY               = 1,
    DAW_CMD_PAUSE              = 2,
    DAW_CMD_STOP               = 3,
    DAW_CMD_SEEK               = 4,
    DAW_CMD_SET_MASTER_VOLUME  = 5,
    DAW_CMD_SET_TRACK_VOLUME   = 6,
    DAW_CMD_SET_TRACK_PAN      = 7,
    DAW_CMD_TOGGLE_TEST_TONE   = 8
} DAWCommandType;

typedef struct DAWCommand {
    uint32_t command_type;
    uint32_t track_id;          // 0 for master bus
    float float_val_1;          // Gain, Frequency, or Pan
    float float_val_2;          // Secondary parameter
    int64_t int_val_1;          // Sample index / seek target
} DAWCommand;
```

### 3.4 Telemetry & Metering Frame
```c
typedef struct DAWMeteringFrame {
    float peak_left;            // Linear peak amplitude [0.0, 1.0+]
    float peak_right;
    float rms_left;             // Root-Mean-Square level
    float rms_right;
    int64_t playhead_frame;     // Current playback position in samples
    uint8_t is_playing;
    uint8_t device_error_flag;  // 1 if an audio device error occurred
} DAWMeteringFrame;
```

---

## 4. Exported C-ABI Functions

### 4.1 Engine Lifecycle
```c
// Creates a new engine instance with the specified configuration.
// Returns DAW_OK and populates out_engine on success.
DAWResult daw_engine_create(const DAWConfig* config, DAWEngineHandle* out_engine);

// Destroys the engine, cleanly stopping all threads and freeing native resources.
DAWResult daw_engine_destroy(DAWEngineHandle engine);

// Returns the API version (major << 16 | minor << 8 | patch).
uint32_t daw_get_api_version(void);
```

### 4.2 Device Management
```c
// Enumerates output devices. Returns count of devices populated in out_devices.
DAWResult daw_enumerate_output_devices(
    DAWEngineHandle engine, 
    DAWDeviceInfo* out_devices, 
    uint32_t max_count, 
    uint32_t* out_actual_count
);
```

### 4.3 Control & Telemetry
```c
// Sends a control command to the audio engine (non-blocking, pushed to SPSC queue).
DAWResult daw_engine_send_command(DAWEngineHandle engine, const DAWCommand* command);

// Polls the latest telemetry frame from the engine (non-blocking, reads from SPSC queue).
// Returns DAW_OK if a frame was read, DAW_ERR_QUEUE_EMPTY if no new frame.
DAWResult daw_engine_poll_telemetry(DAWEngineHandle engine, DAWMeteringFrame* out_frame);
```

---

## 5. Threading and Concurrency Guarantees

1. **`daw_engine_create` / `daw_engine_destroy`:** Must only be called from a single thread (typically the application main or initialization thread).
2. **`daw_engine_send_command`:** Thread-safe for the UI thread. Internally writes to a Single-Producer Single-Consumer (SPSC) ring buffer.
3. **`daw_engine_poll_telemetry`:** Thread-safe for the UI polling loop. Reads from the telemetry SPSC ring buffer.
4. **Audio Callback Independence:** The OS audio thread never executes any of these FFI functions; it only reads from and writes to the pre-allocated lock-free buffers.

---

## 6. Automated C# Binding Generation (`csbindgen`)

To eliminate manual P/Invoke typos and synchronization bugs, `csbindgen` is executed as part of the core build:
```rust
// In tools/generate_bindings or build.rs
csbindgen::Builder::new()
    .input_extern_file("bindings/c_abi/src/lib.rs")
    .csharp_class_name("NativeMethods")
    .csharp_namespace("CustomDAW.Bindings")
    .csharp_dll_name("daw_core")
    .generate_csharp_file("bindings/csharp/NativeMethods.g.cs")
    .unwrap();
```
This guarantees 100% type safety and zero discrepancy between Rust structs and C# memory layouts.
