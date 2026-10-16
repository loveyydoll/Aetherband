using System;
using System.Collections.ObjectModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using RouletteStudio.Desktop.Services;

namespace RouletteStudio.Desktop.ViewModels;

public partial class MainViewModel : ViewModelBase, IDisposable
{
    private readonly AudioService _audioService;
    private readonly DispatcherTimer _meterTimer;

    [ObservableProperty]
    private string _statusText = "Initializing...";

    [ObservableProperty]
    private bool _isPlaying;

    [ObservableProperty]
    private float _masterVolume = 0.8f;

    [ObservableProperty]
    private string _volumeDbText = "-1.9 dB";

    [ObservableProperty]
    private float _peakLeft;

    [ObservableProperty]
    private float _peakRight;

    [ObservableProperty]
    private float _rmsLeft;

    [ObservableProperty]
    private float _rmsRight;

    [ObservableProperty]
    private long _playheadFrames;

    [ObservableProperty]
    private long _totalDurationFrames;

    [ObservableProperty]
    private string _playheadTimeText = "00:00.00";

    [ObservableProperty]
    private string _durationTimeText = "00:00.00";

    [ObservableProperty]
    private double _timelineProgress;

    [ObservableProperty]
    private ObservableCollection<AudioDeviceItem> _devices = new();

    [ObservableProperty]
    private AudioDeviceItem? _selectedDevice;

    [ObservableProperty]
    private bool _testToneEnabled = false;

    [ObservableProperty]
    private float _toneFrequency = 440f;

    [ObservableProperty]
    private ObservableCollection<TrackViewModel> _tracks = new();

    public MainViewModel()
    {
        _audioService = new AudioService();

        if (_audioService.IsInitialized)
        {
            StatusText = "Audio Engine Active";
            LoadDevices();
        }
        else
        {
            StatusText = _audioService.InitializationError is { Length: > 0 } error
                ? $"Audio unavailable: {error}"
                : "Audio engine unavailable. The UI is running without audio.";
        }

        // 60 FPS Telemetry Polling Loop (~16ms)
        _meterTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(16)
        };
        _meterTimer.Tick += OnMeterTick;
        _meterTimer.Start();
    }

    private void LoadDevices()
    {
        Devices.Clear();
        var list = _audioService.GetOutputDevices();
        AudioDeviceItem? defaultItem = null;

        foreach (var dev in list)
        {
            Devices.Add(dev);
            if (dev.IsDefault)
            {
                defaultItem = dev;
            }
        }

        SelectedDevice = defaultItem ?? (Devices.Count > 0 ? Devices[0] : null);
    }

    partial void OnSelectedDeviceChanged(AudioDeviceItem? value)
    {
        if (value != null)
        {
            _audioService.SelectDevice(value.Index);
            StatusText = $"Active Device: {value.Name} ({value.SampleRate} Hz)";
        }
    }

    partial void OnMasterVolumeChanged(float value)
    {
        _audioService.SetMasterVolume(value);

        if (value <= 0.0001f)
        {
            VolumeDbText = "-∞ dB";
        }
        else
        {
            float db = 20.0f * (float)Math.Log10(value);
            VolumeDbText = $"{db:F1} dB";
        }
    }

    partial void OnTestToneEnabledChanged(bool value)
    {
        _audioService.SetTestTone(value, ToneFrequency);
    }

    partial void OnToneFrequencyChanged(float value)
    {
        _audioService.SetTestTone(TestToneEnabled, value);
    }

    [RelayCommand]
    public void Play()
    {
        _audioService.Play();
        IsPlaying = true;
    }

    [RelayCommand]
    public void Pause()
    {
        _audioService.Pause();
        IsPlaying = false;
    }

    [RelayCommand]
    public void Stop()
    {
        _audioService.Stop();
        IsPlaying = false;
        PlayheadFrames = 0;
        PlayheadTimeText = "00:00.00";
        TimelineProgress = 0;
    }

    [RelayCommand]
    public void SetFrequency(object? param)
    {
        if (param != null && float.TryParse(param.ToString(), out float f))
        {
            ToneFrequency = f;
        }
    }

    public void AddTrackFromFile(string path)
    {
        if (!_audioService.IsInitialized) return;

        if (_audioService.LoadTrack(path, out uint trackId))
        {
            string fileName = System.IO.Path.GetFileName(path);
            var trackVm = new TrackViewModel(
                trackId,
                fileName,
                path,
                (id, gain) => _audioService.SetTrackVolume(id, gain),
                (id, pan) => _audioService.SetTrackPan(id, pan),
                (id, muted) => _audioService.MuteTrack(id, muted),
                vm => RemoveTrack(vm)
            );
            Tracks.Add(trackVm);
            StatusText = $"Loaded track: {fileName}";
        }
        else
        {
            StatusText = $"Failed to load audio file: {System.IO.Path.GetFileName(path)}";
        }
    }

    private void RemoveTrack(TrackViewModel vm)
    {
        _audioService.RemoveTrack(vm.Id);
        Tracks.Remove(vm);
        StatusText = $"Removed track: {vm.Name}";
    }

    private void OnMeterTick(object? sender, EventArgs e)
    {
        if (_audioService.PollTelemetry(out var state))
        {
            IsPlaying = state.IsPlaying;
            PeakLeft = Math.Clamp(state.PeakLeft, 0f, 1f);
            PeakRight = Math.Clamp(state.PeakRight, 0f, 1f);
            RmsLeft = Math.Clamp(state.RmsLeft, 0f, 1f);
            RmsRight = Math.Clamp(state.RmsRight, 0f, 1f);
            PlayheadFrames = state.PlayheadFrame;
            TotalDurationFrames = state.TotalDurationFrames;

            // Calculate standard mm:ss.ms time display at 48kHz
            double seconds = state.PlayheadFrame / 48000.0;
            int mins = (int)(seconds / 60);
            double secs = seconds % 60;
            PlayheadTimeText = $"{mins:D2}:{secs:00.00}";

            // Total duration display
            if (state.TotalDurationFrames > 0)
            {
                double totalSeconds = state.TotalDurationFrames / 48000.0;
                int totalMins = (int)(totalSeconds / 60);
                double totalSecs = totalSeconds % 60;
                DurationTimeText = $"{totalMins:D2}:{totalSecs:00.00}";
                TimelineProgress = Math.Clamp((double)state.PlayheadFrame / state.TotalDurationFrames, 0.0, 1.0);
            }
            else
            {
                TimelineProgress = 0.0;
            }
        }
        else if (!IsPlaying)
        {
            // Smooth decay when idle
            PeakLeft = Math.Max(0f, PeakLeft * 0.85f);
            PeakRight = Math.Max(0f, PeakRight * 0.85f);
            RmsLeft = Math.Max(0f, RmsLeft * 0.85f);
            RmsRight = Math.Max(0f, RmsRight * 0.85f);
        }
    }

    public void Dispose()
    {
        _meterTimer.Stop();
        _audioService.Dispose();
        GC.SuppressFinalize(this);
    }
}
