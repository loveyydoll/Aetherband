using System;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Threading;

namespace RouletteStudio.Desktop.Controls;

/// <summary>
/// Draws a precise mirrored peak waveform and an optional playhead.
/// Peaks is an array of absolute peak magnitudes in [0, 1], one value per horizontal bucket.
/// </summary>
public sealed class WaveformControl : Control
{
    public static readonly StyledProperty<float[]?> PeaksProperty =
        AvaloniaProperty.Register<WaveformControl, float[]?>(nameof(Peaks));

    public static readonly StyledProperty<double> ProgressProperty =
        AvaloniaProperty.Register<WaveformControl, double>(nameof(Progress), 0.0);

    public static readonly StyledProperty<IBrush> WaveformBrushProperty =
        AvaloniaProperty.Register<WaveformControl, IBrush>(nameof(WaveformBrush),
            new SolidColorBrush(Color.FromRgb(56, 189, 248)));

    public static readonly StyledProperty<IBrush> PlayheadBrushProperty =
        AvaloniaProperty.Register<WaveformControl, IBrush>(nameof(PlayheadBrush),
            new SolidColorBrush(Color.FromRgb(248, 250, 252)));

    public static readonly StyledProperty<IBrush> LaneBrushProperty =
        AvaloniaProperty.Register<WaveformControl, IBrush>(nameof(LaneBrush),
            new SolidColorBrush(Color.FromRgb(12, 12, 16)));

    public float[]? Peaks
    {
        get => GetValue(PeaksProperty);
        set => SetValue(PeaksProperty, value);
    }

    public double Progress
    {
        get => GetValue(ProgressProperty);
        set => SetValue(ProgressProperty, value);
    }

    public IBrush WaveformBrush
    {
        get => GetValue(WaveformBrushProperty);
        set => SetValue(WaveformBrushProperty, value);
    }

    public IBrush PlayheadBrush
    {
        get => GetValue(PlayheadBrushProperty);
        set => SetValue(PlayheadBrushProperty, value);
    }

    public IBrush LaneBrush
    {
        get => GetValue(LaneBrushProperty);
        set => SetValue(LaneBrushProperty, value);
    }

    static WaveformControl()
    {
        AffectsRender<WaveformControl>(
            PeaksProperty,
            ProgressProperty,
            WaveformBrushProperty,
            PlayheadBrushProperty,
            LaneBrushProperty);
    }

    public override void Render(DrawingContext context)
    {
        var bounds = Bounds;
        if (bounds.Width <= 1 || bounds.Height <= 1)
            return;

        context.FillRectangle(LaneBrush, new Rect(bounds.Size));

        var peaks = Peaks;
        if (peaks == null || peaks.Length == 0)
        {
            // Empty lane hint
            var centerY = bounds.Height * 0.5;
            var pen = new Pen(new SolidColorBrush(Color.FromRgb(40, 40, 48)), 1);
            context.DrawLine(pen, new Point(0, centerY), new Point(bounds.Width, centerY));
            return;
        }

        var midY = bounds.Height * 0.5;
        var halfH = bounds.Height * 0.5 - 2;
        var brush = WaveformBrush;

        // Draw vertical peak stems (mirrored) for a precise DAW look.
        // Map each peak bucket to a pixel column (or sub-pixel average).
        int columns = (int)Math.Max(1, Math.Floor(bounds.Width));
        int peakCount = peaks.Length;

        for (int x = 0; x < columns; x++)
        {
            // Sample the peak array with linear index mapping
            double t = (x + 0.5) / columns;
            int idx = (int)(t * peakCount);
            if (idx >= peakCount) idx = peakCount - 1;
            if (idx < 0) idx = 0;

            float mag = Math.Clamp(peaks[idx], 0f, 1f);
            double h = mag * halfH;
            if (h < 0.5) h = 0.5; // keep a faint floor so silence is still readable

            var rect = new Rect(x, midY - h, 1, h * 2);
            context.FillRectangle(brush, rect);
        }

        // Playhead
        double p = Math.Clamp(Progress, 0.0, 1.0);
        if (p > 0.0 || p == 0.0)
        {
            double x = p * bounds.Width;
            var playPen = new Pen(PlayheadBrush, 1.5);
            context.DrawLine(playPen, new Point(x, 0), new Point(x, bounds.Height));
        }
    }
}
