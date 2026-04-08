# Architecture

## Trust boundaries

- The Mac is the control authority.
- The iPhone can request changes but cannot bypass safety policy.
- SMC access is isolated behind a dedicated bridge that can later move into a
  privileged helper if required.

## Runtime flow

1. `SMCBridge` reads sensors, fan limits, and current fan speeds.
2. `ControlCore` converts sensor snapshots into a bounded command.
3. The Mac app runs a periodic control loop, presents state locally, and exposes a paired remote API.
4. The iPhone app reads telemetry and submits profile or curve requests.
5. The Mac validates every remote request before applying it.

## Remote transport shape

- Discovery: Bonjour on the local network.
- Transport: `Network.framework` over TCP with line-delimited JSON frames.
- Live telemetry: server push using `RemoteResponse.status` frames.
- Commands: request-response messages that validate profile or custom curve changes.
- Profile changes are applied on the Mac controller first, then republished as telemetry.
- Initial implementation should stay local-network only; internet relays can wait.

## Core states

- `systemAuto`
- `profile(quiet | balanced | performance | custom)`
- `manualFixed`
- `emergencyOverride`
- `fallback`

## Safety rules

- Always preserve a model-specific minimum RPM.
- Revert to automatic control when SMC writes fail or sensor reads are invalid.
- Enter emergency override above a critical threshold.
- Rate-limit RPM changes to avoid oscillation.
- Validate all custom curves server-side on the Mac.

## Current hardware status

- `IntelSMCController` now defines the app-facing hardware contract for Intel Macs.
- `AppleSMCTransport` is still a guarded stub and should fail closed until real
  IOKit plumbing is implemented and validated on hardware.
- The dashboard can already swap between mock and Intel-backed runtime sources
  without changing the higher-level app architecture.
- The macOS dashboard now surfaces runtime source, last hardware error, and
  control-loop status to make real-device validation safer.
