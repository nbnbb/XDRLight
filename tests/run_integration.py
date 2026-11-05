#!/usr/bin/env python3
"""Hardware integration checks; intentionally changes brightness temporarily."""
import argparse
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--quick', action='store_true', help='Skip the five-minute soak')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
binary = root / 'XDRLight.app/Contents/MacOS/XDRLight'
check = subprocess.run([str(binary), "--exit-code-test"], capture_output=True, text=True, timeout=15)
if check.returncode != 7:
    raise SystemExit(f"Diagnostic failure exit code broken: {check.returncode}")
print("DiagnosticFailureExitCode=7", flush=True)
cases = [
    ("--conflict-test", 25, ["ElevatedBaselineRejected=1 ForeignCurvePaused=1 ForeignCurvePreserved=1"]),
    ('--self-test', 25, ['Enabled=1', 'GammaApplied=1', 'GammaRestored=1 BrightnessRestored=1', 'SimulatedSeriousThermalShutdown=1']),
    ('--recovery-test', 25, ['SleepSuspended=1 WakeResumed=1 ThermalSuspended=1 ThermalResumed=1 ManualStop=1']),
    ('--render-stall-test', 25, ['RenderedBeforeStall=1 StalledRendererStopped=1 RecoveryBlocked=1']),
]
if not args.quick:
    cases.append(('--soak-test', 340, ['Sustained300Seconds=1 InjectedResetRecovered=1 GammaRestored=1']))
logs = root / 'dist/test-logs'
logs.mkdir(parents=True, exist_ok=True)
for flag, timeout, expected in cases:
    print(f'Running {flag} (close other brightness tools first)', flush=True)
    process = subprocess.Popen([str(binary), flag], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # SIGTERM invokes the app's restore path; never leave a timed-out test running.
        process.terminate()
        try:
            output, _ = process.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            output, _ = process.communicate()
        (logs / (flag[2:] + '.log')).write_text(output)
        raise SystemExit(f'FAIL {flag}: timed out; check display state')
    (logs / (flag[2:] + '.log')).write_text(output)
    print(output, end='', flush=True)
    if process.returncode or any(marker not in output for marker in expected):
        raise SystemExit(f'FAIL {flag}: exit={process.returncode}; quit any running XDRLight and inspect {logs}')
print('All requested hardware checks passed.')
