# QuickVirtual — Implementation Plan (v4)

Single-window macOS app ("QuickVirtual") using Virtualization.framework.
The entire VM (EFI vars, machine identifier, state, main disk) lives in
ONE double-clickable document package: `MyVM.quickvm`, relocatable
anywhere. No settings; resources = half of host RAM and CPU cores.

Minimum deployment target: macOS 27. Not sandboxed.

## 1. Project Setup

1. Xcode project named "QuickVirtual": macOS App, SwiftUI, Swift 6,
   document-based (DocumentGroup). Bundle ID e.g.
   com.example.quickvirtual.
2. Deployment target: macOS 27.
3. Frameworks: Virtualization, DiskImageKit.
4. Entitlements: com.apple.security.virtualization = true.
   App Sandbox: OFF. Hardened Runtime: ON.

## 2. Document Package Format: `.quickvm`

Directory package, double-clickable document.

Layout inside `MyVM.quickvm/`:

- disk.asif        — main disk, Apple Sparse Image Format via
                     DiskImageKit (allocates only written blocks)
- efi_vars.store   — VZEFIVariableStore
- machine_id.bin   — serialized VZGenericMachineIdentifier
- config.json      — { "installed": Bool, "formatVersion": Int,
                       "diskSizeGB": Int, "secureBoot": Bool }

Info.plist:

1. Exported UTI com.example.quickvirtual.vm, conforms to
   com.apple.package + public.data, extension `quickvm`.
2. CFBundleDocumentTypes: role Editor, LSTypeIsPackage = true,
   handler rank Owner.

## 3. Document Model

1. Lightweight document: package URL + parsed config.json only.
   disk.asif accessed in place (never loaded into memory).
2. config.json written atomically; NSFileCoordinator around
   reads/writes.

## 4. UserDefaults

- Key `lastPackageBookmark`: bookmark data of the last opened/created
  package (survives moves/renames).
- On launch without a document: resolve and auto-open; stale →
  welcome view. Refresh bookmark on every open/create.

## 5. Resource Calculation

1. RAM: physicalMemory / 2, clamped to allowed memory range.
2. CPUs: processorCount / 2, clamped to allowed range, min 1.

## 6. VM Configuration Builder

makeConfiguration(package:, isoURL: URL?, secureBoot: Bool):

1. Platform: VZGenericPlatformConfiguration + persisted machine ID.
2. Boot loader: VZEFIBootLoader + persisted VZEFIVariableStore.
   Secure Boot (macOS 27) enabled per config.json's `secureBoot`
   flag (default true on package creation). See §8a for fallback.
3. Memory/CPU from §5.
4. Storage: disk.asif opened via DiskImageKit →
   VZDiskImageStorageDeviceAttachment →
   VZVirtioBlockDeviceConfiguration. ISO (if any) as read-only
   VZUSBMassStorageDeviceConfiguration.
5. Graphics: VZVirtioGraphicsDeviceConfiguration (1280×800).
6. Input: USB keyboard + USB screen-coordinate pointing device.
7. Network: virtio + NAT.
8. Entropy; balloon/sound optional.
9. config.validate().

## 7. Install Flow

1. "Install…" → NSOpenPanel (ISO/IMG).
2. Sheet: disk size in GB (default 20; validate free space).
3. NSSavePanel for package location.
4. Create package: disk.asif (ASIF, requested capacity),
   efi_vars.store, machine_id.bin, config.json
   (installed=false, secureBoot=true).
5. Save bookmark; boot with ISO → .installing.

Aborted install (installed=false, disk exists): reuse disk.asif,
re-prompt only for ISO.

## 8. State Machine & Shutdown Detection

States: noDocument, needsInstall, installing, installed, running.

VZVirtualMachineDelegate:

- guestDidStop:
  - .installing → installed=true, drop ISO → .installed ("Run").
  - .running → .installed.
- didStopWithError → alert; installed stays false during install.

## 8a. Secure Boot Fallback Detection

Secure Boot failure (unsigned kernel/shim) typically manifests as the
guest halting or dropping to EFI without ever booting — not as a host
error. Detection heuristic:

1. Record boot start time on every start().
2. Early-stop rule: if guestDidStop or didStopWithError fires within
   a short window (e.g. < 20 s) AND secureBoot == true:
   - Set secureBoot=false in config.json.
   - Recreate efi_vars.store without Secure Boot (variable store may
     hold SB keys; fresh store avoids inconsistency — safe because a
     failed SB boot wrote no boot entries worth keeping; if this
     happens on an already-installed VM, keep a backup copy of the
     store before recreating and restore on success-path regression).
   - Auto-retry start() once with the same ISO/state. Show a brief
     non-blocking notice: "Secure Boot unsupported by guest —
     retrying without it."
3. Hang case (guest stuck at EFI shell/boot menu, never stops):
   not auto-detectable reliably; out of scope. User force-quits and
   retries; the retry path reads secureBoot from config.json, so a
   manual escape hatch is: if install never completed and a previous
   run exceeded no progress, offer "Retry without Secure Boot" in the
   error/idle UI (single extra button, only shown in this edge case).
4. Only one automatic retry per boot attempt (no loops).
5. Guard against false positives: if the user legitimately shuts down
   within 20 s, worst case is one harmless retry without SB — then
   persisted, changeable later by editing config.json (documented).

## 9. UI

1. DocumentGroup window: VZVirtualMachineView + one button:
   - .needsInstall → "Install…"
   - .installed → "Run"
   - .installing / .running → disabled.
2. Welcome view (no document): "New VM (Install…)" / "Open…".
3. Transient status line for the Secure Boot fallback notice.

## 10. Lifecycle & Edge Cases

1. Quit while running: requestStop(), wait for guestDidStop with
   timeout, then force stop().
2. One open VM at a time; exclusive lock on disk.asif while running.
3. All VZVirtualMachine interaction on the main actor.
4. External volume ejected mid-run → didStopWithError path.
5. Bookmark staleness → welcome view.

## 11. Testing

1. Ubuntu ARM64 ISO on Apple silicon (guest arch must match host).
2. Install → guest shutdown → "Run" → boots from disk (EFI vars
   persistence required).
3. Secure Boot: signed distro (Ubuntu/Fedora) boots with SB on;
   unsigned distro triggers the early-stop fallback, retries without
   SB, and installs; secureBoot=false persists for subsequent runs.
4. False-positive check: shut down a healthy guest within 20 s,
   confirm the single retry is harmless.
5. Double-click .quickvm opens showing "Run".
6. Move/rename package; external drive; ASIF sparseness (file size ≪
   capacity).
7. Resource split across hardware configs.
