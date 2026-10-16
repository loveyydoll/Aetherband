using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using RouletteStudio.Desktop.Native;

namespace RouletteStudio.Desktop.Services
{
    public record AudioDeviceItem(uint Index, string Name, uint SampleRate, ushort Channels, bool IsDefault);

    public record MeteringState(float PeakLeft, float PeakRight, float RmsLeft, float RmsRight, long PlayheadFrame, bool IsPlaying);

    /// <summary>
    /// Safe, high-level C# service wrapping the native Rust audio engine.
    /// </summary>
    public sealed unsafe class AudioService : IDisposable
    {
        private DAWEngine* _engine;
        private bool _disposed;

        public bool IsInitialized => _engine != null;

        public AudioService()
        {
            fixed (DAWEngine** ptr = &_engine)
            {
                int result = NativeMethods.daw_engine_create(ptr);
                if (result != 0)
                {
                    _engine = null;
                }
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

        public bool PollTelemetry(out MeteringState state)
        {
            state = new MeteringState(0, 0, 0, 0, 0, false);
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
