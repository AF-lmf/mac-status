# Phase 10 Hardware Probe: Mac15,9 Thermal Read-Only Verification

**Captured:** 2026-06-24T01:28:38Z  
**Purpose:** Record the final Phase 10 Mac15,9 hardware evidence and anti-scope gates for read-only thermal monitoring.

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
** BUILD SUCCEEDED **
```

The build used the macOS `MacStatus` scheme, not an iOS Simulator destination.

## Temporary Thermal Probe

The probe compiled the product read-only files plus a temporary `/tmp/.../main.swift` into a local executable:

```bash
swiftc -framework IOKit \
  MacStatus/MacStatus/Readers/SMCReader.swift \
  MacStatus/MacStatus/Readers/ThermalReader.swift \
  /tmp/macstatus-thermal-probe.F0jErg/main.swift \
  -o /tmp/macstatus-thermal-probe.F0jErg/thermal-probe
/tmp/macstatus-thermal-probe.F0jErg/thermal-probe
```

Probe output:

```text
snapshot.capturedAt=2026-06-24T01:28:25Z
snapshot.cpuSocTemperatureCelsius=52.52°C
snapshot.systemState=nominal
snapshot.gpuTemperatureCelsius=45.31°C
snapshot.batteryTemperatureCelsius=30.47°C
diagnosticReadings:
cpuSoc key=Te05 type=flt  size=4 value=52.52°C
cpuSoc key=Te0L type=flt  size=4 value=51.59°C
cpuSoc key=Te0P type=flt  size=4 value=53.92°C
cpuSoc key=Te0S type=flt  size=4 value=52.79°C
cpuSoc key=Tf04 type=flt  size=4 value=49.22°C
cpuSoc key=Tf09 type=flt  size=4 value=48.06°C
cpuSoc key=Tf0A type=flt  size=4 value=46.42°C
cpuSoc key=Tf0B type=flt  size=4 value=49.07°C
cpuSoc key=Tf0D type=flt  size=4 value=49.22°C
cpuSoc key=Tf0E type=flt  size=4 value=49.22°C
cpuSoc key=Tf44 type=flt  size=4 value=45.82°C
cpuSoc key=Tf49 type=flt  size=4 value=45.49°C
cpuSoc key=Tf4A type=flt  size=4 value=45.35°C
cpuSoc key=Tf4B type=flt  size=4 value=45.67°C
cpuSoc key=Tf4D type=flt  size=4 value=45.82°C
cpuSoc key=Tf4E type=flt  size=4 value=45.82°C
gpu key=Tf14 type=flt  size=4 value=45.31°C
gpu key=Tf18 type=flt  size=4 value=44.59°C
gpu key=Tf19 type=flt  size=4 value=45.03°C
gpu key=Tf1A type=flt  size=4 value=44.92°C
gpu key=Tf24 type=flt  size=4 value=44.60°C
gpu key=Tf28 type=flt  size=4 value=43.71°C
gpu key=Tf29 type=flt  size=4 value=44.06°C
gpu key=Tf2A type=flt  size=4 value=44.07°C
battery key=TB1T type=flt  size=4 value=31.50°C
battery key=TB2T type=flt  size=4 value=31.30°C
```

## Trust Outcome

- **CPU/SoC:** confirmed trusted Mac15,9 candidate read. `Te05` is in `ThermalSensorCatalog.mac15_9CPUSoCCandidates`, the hardware model is `Mac15,9`, and `ThermalReader.readValue()` selected `52.52°C`. If the model gate or catalog candidate read fails on another machine, the UI remains `CPU/SoC N/A`; `ProcessInfo.thermalState` is not used as a temperature substitute.
- **ProcessInfo:** `snapshot.systemState=nominal`; this is rendered only as the separate `系统状态` row.
- **GPU:** confirmed Mac15,9 GPU candidate read. `Tf14` is in `ThermalSensorCatalog.mac15_9GPUCandidates`, and `ThermalReader.readValue()` selected `45.31°C`.
- **Battery:** `ThermalReader.readValue()` selected `30.47°C` from `AppleSmartBattery` `Temperature`; SMC fallback diagnostics also showed `TB1T=31.50°C` and `TB2T=31.30°C`.
- **N/A behavior:** unsupported models, absent keys, untrusted candidates, and transient read failures remain normal quiet inline `N/A`/`未知` states when the `散热区块` is visible.

## Final Source Gates

### no SMC write / no fan / no control / no helper or XPC

Command:

```bash
! rg -n "cmdWriteBytes|writeBytes|writeValue|writeRaw|FNum|FS!|F[0-9](Ac|Mn|Mx|Tg|Md|md)|RPM|风扇|FanController|helper|XPC" MacStatus/MacStatus
```

Output:

```text
no matches (rg exit=1 before shell negation)
```

### no status-bar thermal / no persistence metric surface

Command:

```bash
! rg -n "thermal|Thermal|散热" MacStatus/MacStatus/Storage MacStatus/MacStatus/UI/StatusBarManager.swift MacStatus/MacStatus/Utils/Metric.swift
```

Output:

```text
no matches (rg exit=1 before shell negation)
```

### no SSD / SMART / NVMe reader

Command:

```bash
! rg -n "SSD|SMART|NVMe|DiskArbitration|IOBlockStorage|smartctl" MacStatus/MacStatus
```

Output:

```text
no matches (rg exit=1 before shell negation)
```

### no notifications or alerts for thermal read failures

Command:

```bash
! rg -n "thermal.*notification|notification.*thermal|Thermal.*notification|notification.*Thermal|Alert\(|alert.*thermal|thermal.*alert|告警.*散热|散热.*告警" MacStatus/MacStatus
```

Output:

```text
no matches (rg exit=1 before shell negation)
```

### no MetricSample/history thermal fields

Command:

```bash
! rg -n "thermal|Thermal|散热" MacStatus/MacStatus/Storage MacStatus/MacStatus/Utils/Metric.swift
```

Output:

```text
no matches (rg exit=1 before shell negation)
```

### Dashboard width unchanged

Command:

```bash
rg -n "\.frame\(width: 320\)" MacStatus/MacStatus/UI/Views/DashboardView.swift
```

Output:

```text
129:        .frame(width: 320)
```

## Conclusion

Phase 10 closes with read-only, popover-only thermal monitoring on `Mac15,9`. CPU/SoC, GPU, and battery values were read from the allowed sources above; untrusted or unavailable sources stay `N/A`. Final gates show no SMC write API, no fan/RPM/control UI, no helper/XPC, no status-bar thermal metric, no thermal persistence/history fields, no SSD reader, and no notification/alert scope.
