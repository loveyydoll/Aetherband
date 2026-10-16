using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using NAudio.Wave;

namespace RouletteStudio.Desktop.Services;

/// <summary>
/// Offline peak extraction for timeline waveforms.
/// Produces a fixed-length array of absolute peak magnitudes in [0, 1].
/// Runs off the UI thread.
/// </summary>
public static class PeakGenerator
{
    public const int DefaultResolution = 2048;

    /// <summary>
    /// Generate peak magnitudes for <paramref name="filePath"/>.
    /// Returns null on failure.
    /// </summary>
    public static Task<float[]?> GenerateAsync(string filePath, int resolution = DefaultResolution, CancellationToken ct = default)
    {
        return Task.Run(() => Generate(filePath, resolution, ct), ct);
    }

    public static float[]? Generate(string filePath, int resolution = DefaultResolution, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(filePath) || !File.Exists(filePath))
            return null;

        if (resolution < 16)
            resolution = 16;

        try
        {
            using var reader = CreateReader(filePath);
            if (reader == null)
                return null;

            var sampleProvider = reader.ToSampleProvider();
            int channels = sampleProvider.WaveFormat.Channels;
            if (channels <= 0)
                return null;

            // Read all samples (or a large prefix for very long files)
            const int maxFrames = 20_000_000; // ~ safety cap
            var buffer = new float[8192 * channels];
            var all = new float[Math.Min(maxFrames * channels, 4_000_000 * channels)];
            int written = 0;

            while (written + buffer.Length <= all.Length)
            {
                ct.ThrowIfCancellationRequested();
                int read = sampleProvider.Read(buffer, 0, buffer.Length);
                if (read <= 0)
                    break;
                Array.Copy(buffer, 0, all, written, read);
                written += read;
            }

            int totalFrames = written / channels;
            if (totalFrames <= 0)
                return new float[resolution];

            var peaks = new float[resolution];
            double framesPerBucket = (double)totalFrames / resolution;

            for (int i = 0; i < resolution; i++)
            {
                ct.ThrowIfCancellationRequested();
                int start = (int)(i * framesPerBucket);
                int end = (int)((i + 1) * framesPerBucket);
                if (end > totalFrames) end = totalFrames;
                if (start >= end) start = Math.Max(0, end - 1);

                float peak = 0f;
                for (int f = start; f < end; f++)
                {
                    int baseIdx = f * channels;
                    // Peak across channels
                    for (int c = 0; c < channels; c++)
                    {
                        float a = Math.Abs(all[baseIdx + c]);
                        if (a > peak) peak = a;
                    }
                }
                peaks[i] = peak > 1f ? 1f : peak;
            }

            return peaks;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch
        {
            return null;
        }
    }

    private static WaveStream? CreateReader(string path)
    {
        var ext = Path.GetExtension(path).ToLowerInvariant();
        try
        {
            return ext switch
            {
                ".wav" => new WaveFileReader(path),
                ".aiff" or ".aif" => new AiffFileReader(path),
                ".mp3" => new Mp3FileReader(path),
                // MediaFoundationReader covers m4a/aac/flac on Windows when codecs are present
                _ => new MediaFoundationReader(path),
            };
        }
        catch
        {
            try
            {
                return new MediaFoundationReader(path);
            }
            catch
            {
                return null;
            }
        }
    }
}
