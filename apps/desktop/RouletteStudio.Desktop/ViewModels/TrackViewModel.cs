using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System;

namespace RouletteStudio.Desktop.ViewModels;

public partial class TrackViewModel : ViewModelBase
{
    private readonly Action<uint, float> _onVolumeChanged;
    private readonly Action<uint, float> _onPanChanged;
    private readonly Action<uint, bool> _onMuteChanged;
    private readonly Action<TrackViewModel> _onRemove;

    public uint Id { get; }

    [ObservableProperty]
    private string _name = "Audio Track";

    [ObservableProperty]
    private string _filePath = string.Empty;

    [ObservableProperty]
    private float _volume = 0.8f;

    [ObservableProperty]
    private string _volumeDbText = "-1.9 dB";

    [ObservableProperty]
    private float _pan = 0.5f;

    [ObservableProperty]
    private string _panText = "C";

    [ObservableProperty]
    private bool _isMuted;

    /// <summary>
    /// Absolute peak magnitudes [0,1] for waveform drawing. Null while loading.
    /// </summary>
    [ObservableProperty]
    private float[]? _peaks;

    /// <summary>
    /// 0–1 playhead progress shared from the main transport for this lane.
    /// </summary>
    [ObservableProperty]
    private double _progress;

    [ObservableProperty]
    private bool _isGeneratingPeaks;

    public TrackViewModel(
        uint id,
        string name,
        string filePath,
        Action<uint, float> onVolumeChanged,
        Action<uint, float> onPanChanged,
        Action<uint, bool> onMuteChanged,
        Action<TrackViewModel> onRemove)
    {
        Id = id;
        Name = name;
        FilePath = filePath;
        _onVolumeChanged = onVolumeChanged;
        _onPanChanged = onPanChanged;
        _onMuteChanged = onMuteChanged;
        _onRemove = onRemove;
    }

    partial void OnVolumeChanged(float value)
    {
        _onVolumeChanged(Id, value);
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

    partial void OnPanChanged(float value)
    {
        _onPanChanged(Id, value);
        if (Math.Abs(value - 0.5f) < 0.02f)
        {
            PanText = "C";
        }
        else if (value < 0.5f)
        {
            int p = (int)((0.5f - value) * 200);
            PanText = $"L{p}%";
        }
        else
        {
            int p = (int)((value - 0.5f) * 200);
            PanText = $"R{p}%";
        }
    }

    partial void OnIsMutedChanged(bool value)
    {
        _onMuteChanged(Id, value);
    }

    [RelayCommand]
    public void ToggleMute()
    {
        IsMuted = !IsMuted;
    }

    [RelayCommand]
    public void Remove()
    {
        _onRemove(this);
    }
}
