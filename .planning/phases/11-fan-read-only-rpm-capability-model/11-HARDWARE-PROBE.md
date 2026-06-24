# Phase 11 Hardware Probe: Mac15,9 Fan Read-Only Verification

**Captured:** 2026-06-24T07:27:13Z
**Purpose:** Record Phase 11 Mac15,9 read-only fan RPM/capability evidence before closing the fail-closed boundary.

## Hardware and OS

Command:

```bash
sysctl -n hw.model
sw_vers
```

Output:

```text
Mac15,9
ProductName:		macOS
ProductVersion:		26.5.1
BuildVersion:		25F80
```

## Build Gate

Command:

```bash
xcodebuild -project MacStatus/MacStatus.xcodeproj -scheme MacStatus -configuration Debug -derivedDataPath build build
```

Result:

```text
2026-06-24 15:26:20.994 xcodebuild[53446:15884697] [MT] IDERunDestination: Supported platforms for the buildables in the current scheme is empty.
--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64, id:00006031-000830200A44001C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00006031-000830200A44001C, name:My Mac }
{ platform:macOS, name:Any Mac }
note: Building targets in dependency order
note: Target dependency graph (1 target)
    Target 'MacStatus' in project 'MacStatus' (no dependencies)
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'MacStatus' from project 'MacStatus')
** BUILD SUCCEEDED **
```

The build used the macOS `MacStatus` scheme and completed successfully.

## Temporary Fan Probe

The probe compiled the product read-only files plus a temporary `/tmp/.../main.swift` into a local executable:

```bash
swiftc -framework IOKit \
  MacStatus/MacStatus/Readers/SMCReader.swift \
  MacStatus/MacStatus/Readers/FanReader.swift \
  /tmp/macstatus-fan-probe.7fDwfC/main.swift \
  -o /tmp/macstatus-fan-probe.7fDwfC/fan-probe
/tmp/macstatus-fan-probe.7fDwfC/fan-probe
```

The temporary probe called only `FanReader.setup()`, `FanReader.readValue()`, `FanReader.diagnosticReadings()`, `sysctlbyname("hw.model")`, and `sw_vers`. It performed read-only diagnostics only: no write, no write/readback, no `FS!` write, no `F{i}Tg` write, no helper/XPC, and no fan control command.

Probe output:

```text
probe.readOnly=true
probe.noWrite=true
hw.model=Mac15,9
sw_vers:
ProductName:		macOS
ProductVersion:		26.5.1
BuildVersion:		25F80
FanSnapshot.capturedAt=2026-06-24T07:27:13Z
FanSnapshot.supportState=supported
FanSnapshot.fanCount=2
FanReading index=0 label=风扇 1 currentRPM=1336.60 minRPM=1350.00 maxRPM=5349.00 targetRPM=1350.00 capabilities={rpmReadable=true boundsReadable=true targetReadable=true safeControlAvailable=false}
FanReading index=1 label=风扇 2 currentRPM=1458.82 minRPM=1458.00 maxRPM=5777.00 targetRPM=1458.00 capabilities={rpmReadable=true boundsReadable=true targetReadable=true safeControlAvailable=false}
FanDiagnosticReading rows:
key=FNum type=ui8  size=1 numericValue=2.00 rawBytes=[0x02]
key=F0Ac type=flt  size=4 numericValue=1336.60 rawBytes=[0x38, 0x13, 0xA7, 0x44]
key=F0Mn type=flt  size=4 numericValue=1350.00 rawBytes=[0x00, 0xC0, 0xA8, 0x44]
key=F0Mx type=flt  size=4 numericValue=5349.00 rawBytes=[0x00, 0x28, 0xA7, 0x45]
key=F0Tg type=flt  size=4 numericValue=1350.00 rawBytes=[0x00, 0xC0, 0xA8, 0x44]
key=F0Sf type=ui16 size=2 numericValue=0.00 rawBytes=[0x00, 0x00]
key=F0ID type=nil size=nil numericValue=nil rawBytes=[]
key=F0Md type=ui8  size=1 numericValue=0.00 rawBytes=[0x00]
key=F0md type=nil size=nil numericValue=nil rawBytes=[]
key=F1Ac type=flt  size=4 numericValue=1458.82 rawBytes=[0x33, 0x5A, 0xB6, 0x44]
key=F1Mn type=flt  size=4 numericValue=1458.00 rawBytes=[0x00, 0x40, 0xB6, 0x44]
key=F1Mx type=flt  size=4 numericValue=5777.00 rawBytes=[0x00, 0x88, 0xB4, 0x45]
key=F1Tg type=flt  size=4 numericValue=1458.00 rawBytes=[0x00, 0x40, 0xB6, 0x44]
key=F1Sf type=ui16 size=2 numericValue=0.00 rawBytes=[0x00, 0x00]
key=F1ID type=nil size=nil numericValue=nil rawBytes=[]
key=F1Md type=ui8  size=1 numericValue=0.00 rawBytes=[0x00]
key=F1md type=nil size=nil numericValue=nil rawBytes=[]
key=F2Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F2Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F2Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F2Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F2Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F2ID type=nil size=nil numericValue=nil rawBytes=[]
key=F2Md type=nil size=nil numericValue=nil rawBytes=[]
key=F2md type=nil size=nil numericValue=nil rawBytes=[]
key=F3Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F3Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F3Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F3Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F3Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F3ID type=nil size=nil numericValue=nil rawBytes=[]
key=F3Md type=nil size=nil numericValue=nil rawBytes=[]
key=F3md type=nil size=nil numericValue=nil rawBytes=[]
key=F4Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F4Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F4Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F4Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F4Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F4ID type=nil size=nil numericValue=nil rawBytes=[]
key=F4Md type=nil size=nil numericValue=nil rawBytes=[]
key=F4md type=nil size=nil numericValue=nil rawBytes=[]
key=F5Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F5Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F5Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F5Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F5Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F5ID type=nil size=nil numericValue=nil rawBytes=[]
key=F5Md type=nil size=nil numericValue=nil rawBytes=[]
key=F5md type=nil size=nil numericValue=nil rawBytes=[]
key=F6Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F6Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F6Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F6Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F6Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F6ID type=nil size=nil numericValue=nil rawBytes=[]
key=F6Md type=nil size=nil numericValue=nil rawBytes=[]
key=F6md type=nil size=nil numericValue=nil rawBytes=[]
key=F7Ac type=nil size=nil numericValue=nil rawBytes=[]
key=F7Mn type=nil size=nil numericValue=nil rawBytes=[]
key=F7Mx type=nil size=nil numericValue=nil rawBytes=[]
key=F7Tg type=nil size=nil numericValue=nil rawBytes=[]
key=F7Sf type=nil size=nil numericValue=nil rawBytes=[]
key=F7ID type=nil size=nil numericValue=nil rawBytes=[]
key=F7Md type=nil size=nil numericValue=nil rawBytes=[]
key=F7md type=nil size=nil numericValue=nil rawBytes=[]
key=FS!  type=nil size=nil numericValue=nil rawBytes=[]
key=Ftst type=ui8  size=1 numericValue=0.00 rawBytes=[0x00]
```

## Probe Outcome

- `Mac15,9` is the Phase 11 validation target and exposed `FNum=2` as `ui8 ` with raw byte `0x02`.
- `FanSnapshot.supportState=supported` with two `FanReading` rows.
- `风扇 1` and `风扇 2` both reported current RPM, min RPM, max RPM, target RPM, and independent capability booleans.
- `safeControlAvailable=false` for both fans, so readable telemetry does not imply control availability.
- `F0ID` and `F1ID` were unavailable. There is no reliable position evidence, so the app keeps numbered labels (`风扇 1`, `风扇 2`) and does not infer `左风扇` / `右风扇`.
- `FS! ` was unavailable in read-only diagnostics, and the probe did not attempt any write or control operation.
