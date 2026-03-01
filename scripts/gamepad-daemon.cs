#!/usr/bin/env -S dotnet run
#:package Gamepad@1.1.0

using System.Diagnostics;
using Gamepad; // from nahueltaibo/gamepad

// -------- Config --------
// Welke systemd unit beheert jouw kiosk chromium? (pas aan!)
var chromiumUnit = Environment.GetEnvironmentVariable("CHROMIUM_UNIT") ?? "chromium-kiosk.service";

// Debounce / safety
var comboHoldMs = int.TryParse(Environment.GetEnvironmentVariable("COMBO_HOLD_MS"), out var ms) ? ms : 250;

// ------------------------

Console.WriteLine($"[gp] starting, device=/dev/input/js*, chromiumUnit={chromiumUnit}");

// Per-controller state: elk apparaat heeft zijn eigen "welke knoppen zijn ingedrukt"
var controllers = new Dictionary<string, GamepadController>();
var pressedSets = new Dictionary<string, HashSet<byte>>();
object lockObj = new();
var lastActionAt = DateTimeOffset.MinValue;

void HandleCombo(HashSet<byte> pressed)
{
    // Basis combo: Start (7) + Select (6) ingedrukt houden
    // Let op: button-namen kunnen per controller verschillen.
    // Op veel pads is "Select" = Back, "Start" = Start.
    if (!pressed.Contains(6) || !pressed.Contains(7)) return;

    // simpele debounce: niet 10x dezelfde actie
    if ((DateTimeOffset.UtcNow - lastActionAt).TotalMilliseconds < comboHoldMs) return;

    // Acties:
    // - Start+Select+A = start kiosk met hugobox.nl
    // - Start+Select+B = start kiosk met dev.hugobox.nl
    // - Start+Select+X = shutdown
    // - Start+Select+Y = stop kiosk (terug naar desktop)
    if (pressed.Contains(0))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+A => start kiosk (hugobox.nl)");
        SetKioskUrl("https://hugobox.nl");
        Run("systemctl", $"restart {chromiumUnit}");
    }
    else if (pressed.Contains(1))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+B => start kiosk (dev.hugobox.nl)");
        SetKioskUrl("https://dev.hugobox.nl");
        Run("systemctl", $"restart {chromiumUnit}");
    }
    else if (pressed.Contains(2))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+X => shutdown");
        Run("systemctl", "poweroff");
    }
    else if (pressed.Contains(3))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+Y => stop kiosk (desktop)");
        Run("systemctl", $"stop {chromiumUnit}");
    }
}

void AddController(string path)
{
    lock (lockObj)
    {
        if (controllers.ContainsKey(path)) return;
        try
        {
            var pressed = new HashSet<byte>();
            var gc = new GamepadController(path);
            gc.ButtonChanged += (_, e) =>
            {
                //Console.WriteLine($"[{path}] Button {e.Button} pressed={e.Pressed}");
                if (e.Pressed) pressed.Add(e.Button);
                else pressed.Remove(e.Button);
                HandleCombo(pressed);
            };
            controllers[path] = gc;
            pressedSets[path] = pressed;
            Console.WriteLine($"[gp] connected: {path}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[gp] failed to open {path}: {ex.Message}");
        }
    }
}

void RemoveController(string path)
{
    lock (lockObj)
    {
        if (controllers.TryGetValue(path, out var gc))
        {
            try { gc.Dispose(); } catch { }
            controllers.Remove(path);
            pressedSets.Remove(path);
            Console.WriteLine($"[gp] disconnected: {path}");
        }
    }
}

Console.WriteLine("[gp] multi-device mode: watching /dev/input/js*");

// Voeg bestaande apparaten toe
try
{
    foreach (var path in Directory.GetFiles("/dev/input", "js*").OrderBy(p => p))
        AddController(path);
}
catch (Exception ex)
{
    Console.WriteLine($"[gp] warning: could not enumerate /dev/input: {ex.Message}");
}

// Bewaak nieuwe en verwijderde apparaten (bijv. bij Bluetooth reconnect)
var watcher = new FileSystemWatcher("/dev/input", "js*")
{
    EnableRaisingEvents = true
};
watcher.Created += (_, e) =>
{
    Console.WriteLine($"[gp] new device detected: {e.FullPath}");
    // Korte vertraging zodat het apparaatbestand volledig klaar is voordat we het openen
    Thread.Sleep(500);
    AddController(e.FullPath);
};
watcher.Deleted += (_, e) => RemoveController(e.FullPath);

Console.WriteLine("[gp] listening... (Ctrl+C to stop)");
var stop = new ManualResetEventSlim(false);

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    stop.Set();
};

stop.Wait();
watcher.Dispose();

static void SetKioskUrl(string url)
{
    try
    {
        const string configFile = "/etc/hugobox/config.env";
        if (!File.Exists(configFile))
        {
            Console.WriteLine($"[warn] Config file not found: {configFile}");
            return;
        }

        var lines = File.ReadAllLines(configFile);
        var updated = false;

        for (int i = 0; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("HUGOBOX_URL="))
            {
                lines[i] = $"HUGOBOX_URL=\"{url}\"";
                updated = true;
                break;
            }
        }

        if (updated)
        {
            File.WriteAllLines(configFile, lines);
            Console.WriteLine($"[config] Updated HUGOBOX_URL to {url}");
        }
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[err] Failed to update config: {ex.Message}");
    }
}

static int Run(string file, string args)
{
    try
    {
        var psi = new ProcessStartInfo
        {
            FileName = file,
            Arguments = args,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false
        };

        using var p = Process.Start(psi)!;
        p.WaitForExit();

        var stdout = p.StandardOutput.ReadToEnd().Trim();
        var stderr = p.StandardError.ReadToEnd().Trim();

        if (stdout.Length > 0) Console.WriteLine($"[cmd] {stdout}");
        if (stderr.Length > 0) Console.WriteLine($"[cmd-err] {stderr}");

        return p.ExitCode;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[err] failed to run '{file} {args}': {ex}");
        return -1;
    }
}
