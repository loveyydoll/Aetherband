using Avalonia;
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace RouletteStudio.Desktop;

sealed class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        catch (Exception ex)
        {
            var logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Aetherband");
            var logPath = Path.Combine(logDirectory, "startup.log");

            try
            {
                Directory.CreateDirectory(logDirectory);
                File.AppendAllText(logPath,
                    $"[{DateTimeOffset.Now:O}] Fatal startup exception{Environment.NewLine}{ex}{Environment.NewLine}{Environment.NewLine}");
            }
            catch
            {
                // Preserve the original startup error even if diagnostics cannot be written.
            }

            var message = $"Aetherband could not start.\n\n{ex.Message}\n\nDetails: {logPath}";
            MessageBoxW(IntPtr.Zero, message, "Aetherband startup error", 0x10);
            Environment.ExitCode = 1;
        }
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "MessageBoxW")]
    private static extern int MessageBoxW(IntPtr hWnd, string text, string caption, uint type);

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<App>()
            .UsePlatformDetect()
#if DEBUG
            .WithDeveloperTools()
#endif
            .WithInterFont()
            .LogToTrace();
}
