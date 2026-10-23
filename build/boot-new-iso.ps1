$ErrorActionPreference = 'Stop'

# ISO launch helper for an explicitly UEFI-configured VirtualBox test VM.
# It ensures EFI is enabled on the VM and refuses legacy boot checks entirely.
$vbox = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
$vm = 'ContinuityOS-20261014-rebuild-check'
$iso = if ($env:CONTINUITY_ISO_PATH) { $env:CONTINUITY_ISO_PATH } else { Join-Path $PSScriptRoot '..\build\out-rebuild-20261017-uefi\continuityos-2026.10.17-x86_64.iso' }
$iso = [IO.Path]::GetFullPath($iso)

if (-not (Test-Path -LiteralPath $vbox)) { throw "VBoxManage not found: $vbox" }
if (-not (Test-Path -LiteralPath $iso)) { throw "ISO not found: $iso" }

$info = & $vbox showvminfo $vm --machinereadable
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
if (($info | Select-String '^firmware="EFI"$').Count -eq 0) {
  & $vbox modifyvm $vm --firmware efi
  if ($LASTEXITCODE -ne 0) { throw "Could not enable EFI firmware for VM '$vm'." }
  $info = & $vbox showvminfo $vm --machinereadable
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  if (($info | Select-String '^firmware="EFI"$').Count -eq 0) {
    throw "VM '$vm' did not report EFI firmware after enabling it."
  }
}

if (($info | Select-String '^VMState="running"$').Count -gt 0) {
  & $vbox controlvm $vm poweroff
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Start-Sleep -Seconds 3
}

& $vbox storageattach $vm --storagectl SATA --port 0 --device 0 --type dvddrive --medium emptydrive
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $vbox storageattach $vm --storagectl SATA --port 0 --device 0 --type dvddrive --medium $iso
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $vbox startvm $vm --type headless
exit $LASTEXITCODE