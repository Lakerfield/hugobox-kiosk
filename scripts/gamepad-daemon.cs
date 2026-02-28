#!/usr/bin/env -S dotnet run
#:package Gamepad@1.1.0

using System.Diagnostics;
using Gamepad; // from nahueltaibo/gamepad

// -------- Config --------
// Welke joystick device? (default: /dev/input/js0)
var devicePath = Environment.GetEnvironmentVariable("GP_DEVICE") ?? "/dev/input/js0";

// Welke systemd unit beheert jouw kiosk chromium? (pas aan!)
var chromiumUnit = Environment.GetEnvironmentVariable("CHROMIUM_UNIT") ?? "chromium-kiosk.service";

// Debounce / safety
var comboHoldMs = int.TryParse(Environment.GetEnvironmentVariable("COMBO_HOLD_MS"), out var ms) ? ms : 250;

// ------------------------

Console.WriteLine($"[gp] starting, device={devicePath}, chromiumUnit={chromiumUnit}");

using var gamepad = new GamepadController(devicePath);

// We onthouden welke knoppen nu ingedrukt zijn
var pressed = new HashSet<byte>();
var lastActionAt = DateTimeOffset.MinValue;

gamepad.ButtonChanged += (_, e) =>
{
    //Console.WriteLine($"Button {e.Button} pressed={e.Pressed}");

    if (e.Pressed) pressed.Add(e.Button);
    else pressed.Remove(e.Button);

    // Basis combo: Start + Select ingedrukt houden
    if (!IsComboBasePressed()) return;

    // simpele debounce: niet 10x dezelfde actie
    if ((DateTimeOffset.UtcNow - lastActionAt).TotalMilliseconds < comboHoldMs) return;

    // Acties:
    // - Start+Select+A = (her)start chromium
    // - Start+Select+X = shutdown os
    // - Start+Select+B = close chromium, go to desktop (stop kiosk service)
    if (pressed.Contains(0))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+A => restart chromium");
        Run("systemctl", $"restart {chromiumUnit}");
        return;
    }

    if (pressed.Contains(2))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+B => shutdown");
        Run("systemctl", "poweroff");
        return;
    }

    if (pressed.Contains(1))
    {
        lastActionAt = DateTimeOffset.UtcNow;
        Console.WriteLine("[gp] combo: Start+Select+X => stop chromium (desktop)");
        Run("systemctl", $"stop {chromiumUnit}");
        return;
    }
};

Console.WriteLine("[gp] listening... (Ctrl+C to stop)");
var stop = new ManualResetEventSlim(false);

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    stop.Set();
};

stop.Wait();

bool IsComboBasePressed()
{
    // Let op: button-namen kunnen per controller verschillen.
    // Op veel pads is "Select" = Back, "Start" = Start.
    return pressed.Contains(6) && pressed.Contains(7);
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
