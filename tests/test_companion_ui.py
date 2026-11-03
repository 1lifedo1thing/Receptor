#!/usr/bin/env python3
"""Run the real WinForms pairing flow using isolated preferences and loopback."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
compiler = Path(os.environ['WINDIR']) / 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
output = ROOT / 'build/desktop/CompanionUiTest.exe'
output.parent.mkdir(parents=True, exist_ok=True)
subprocess.run([str(compiler), '/nologo', '/target:exe', '/warnaserror+', '/main:CompanionUiTest',
                '/reference:System.Security.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll',
                '/out:' + str(output), str(ROOT / 'tests/companion_ui.cs'),
                *[str(ROOT / 'Desktop' / name) for name in ['Program.cs', 'CompanionServer.cs', 'ConnectionSettings.cs', 'RemoteProtocol.cs', 'RemoteBroker.cs', 'RemoteControlForm.cs']]], check=True)
with tempfile.TemporaryDirectory(prefix='receptor-ui-test-') as temporary:
    subprocess.run([str(output), str(Path(temporary) / 'pairing.dat')], check=True, timeout=30)
