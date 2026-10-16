using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using RouletteStudio.Desktop.Native;

namespace RouletteStudio.Desktop.Services
{
    public record AudioDeviceItem(uint Index, string Name, uint SampleRate, ushort Channels, bool IsDefault);

    public record MeteringState(float PeakLeft, float PeakRight, float RmsLeft, float RmsRight, long PlayheadFrame, long TotalDurationFrames, bool IsPlaying);

    /// <summary>
    /// Safe, high-level C# service wrapping the native Rust audio engine.
    /// </summary>
    public sealed unsafe class AudioService : IDisposable
    {
        private DAWEngine* _engine;
        private bool _disposed;

        public bool IsInitialized => _engine != null;
        public string? InitializationError { get; private set; }

        public AudioService()
        {
            try
            {
                fixed (DAWEngine** ptr = &_engine)
                {
                    int result = NativeMethods.daw_engine_create(ptr);
                    if (result != 0)
                    {
                        _engine = null;
                        InitializationError = $"Native audio engine initialization failed (error code {result}).";
                    }
                }
            }
            catch (Exception ex) when (
                ex is DllNotFoundException ||
                ex is EntryPointNotFoundException ||
                ex is BadImageFormatException ||
                ex is SEHException)
            {
                _engine = null;
                InitializationError = $"Could not load or initialize the native Rust audio engine: {ex.Message}";
            }
        }

        public void Play()
        {
            if (_engine != null)
                NativeMethods.daw_engine_play(_engine);
        }

        public void Pause()
        {
            if (_engine != null)
                NativeMethods.daw_engine_pause(_engine);
        }

        public void Stop()
        {
            if (_engine != null)
                NativeMethods.daw_engine_stop(_engine);
        }

        public void SetMasterVolume(float gain)
        {
            if (_engine != null)
                NativeMethods.daw_engine_set_master_volume(_engine, gain);
        }

        public void SetTestTone(bool enabled, float freqHz)
        {
            if (_engine != null)
                NativeMethods.daw_engine_set_test_tone(_engine, enabled ? (byte)1 : (byte)0, freqHz);
        }

        public bool LoadTrack(string filePath, out uint trackId)
        {
            trackId = 0;
            if (_engine == null) return false;

            byte[] utf8Bytes = System.Text.Encoding.UTF8.GetBytes(filePath + "\0");
            fixed (byte* pathPtr = utf8Bytes)
            {
                uint id = 0;
                int res = NativeMethods.daw_engine_load_track(_engine, pathPtr, &id);
                if (res == 0)
                {
                    trackId = id;
                    return true;
                }
            }
            return false;
        }

        public bool RemoveTrack(uint trackId)
        {
            if (_engine == null) return false;
            return NativeMethods.daw_engine_remove_track(_engine, trackId) == 0;
        }

        public void SetTrackVolume(uint trackId, float gain)
        {
            if (_engine != null)
                NativeMethods.daw_engine_set_track_volume(_engine, trackId, gain);
        }

        public void SetTrackPan(uint trackId, float pan)
        {
            if (_engine != null)
                NativeMethods.daw_engine_set_track_pan(_engine, trackId, pan);
        }

        public void MuteTrack(uint trackId, bool muted)
        {
            if (_engine != null)
                NativeMethods.daw_engine_mute_track(_engine, trackId, muted ? (byte)1 : (byte)0);
        }

        public int GetTrackCount()
        {
            if (_engine == null) return 0;
            return NativeMethods.daw_engine_get_track_count(_engine);
        }

        public bool PollTelemetry(out MeteringState state)
        {
            state = new MeteringState(0, 0, 0, 0, 0, 0, false);
            if (_engine == null) return false;

            DAWMeteringFrame frame;
            int result = NativeMethods.daw_engine_poll_telemetry(_engine, &frame);
            if (result == 0)
            {
                state = new MeteringState(
                    frame.peak_left,
                    frame.peak_right,
                    frame.rms_left,
                    frame.rms_right,
                    frame.playhead_frame,
                    frame.total_duration_frames,
                    frame.is_playing != 0
                );
                return true;
            }
            return false;
        }

        public IReadOnlyList<AudioDeviceItem> GetOutputDevices()
        {
            var list = new List<AudioDeviceItem>();
            if (_engine == null) return list;

            int count = NativeMethods.daw_engine_get_device_count(_engine);
            for (uint i = 0; i < count; i++)
            {
                DAWDeviceInfo info = default;
                if (NativeMethods.daw_engine_get_device_info(_engine, i, &info) == 0)
                {
                    string name = Marshal.PtrToStringAnsi((IntPtr)info.name) ?? $"Device {i}";
                    list.Add(new AudioDeviceItem(info.index, name, info.default_sample_rate, info.channels, info.is_default != 0));
                }
            }
            return list;
        }

        public void SelectDevice(uint index)
        {
            if (_engine != null)
                NativeMethods.daw_engine_select_device(_engine, index);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                if (_engine != null)
                {
                    NativeMethods.daw_engine_destroy(_engine);
                    _engine = null;
                }
                _disposed = true;
            }
            GC.SuppressFinalize(this);
        }

        ~AudioService()
        {
            Dispose();
        }
    }
}
