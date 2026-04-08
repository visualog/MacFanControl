# MFC

Mac Fan Control architecture scaffold for:

- a macOS app that owns SMC access and thermal control
- an iPhone app that acts as a paired remote controller

This repository starts with shared Swift packages so the risky parts of the
system can be designed and tested before building full app targets.

## Layout

- `apps/MacFanControl`: planned macOS app target shell
- `apps/iPhoneRemote`: planned iPhone app target shell
- `packages/SharedModels`: cross-platform domain models
- `packages/ControlCore`: thermal control engine and policy logic
- `packages/RemoteProtocol`: API and WebSocket message contracts
- `packages/SMCBridge`: low-level SMC abstractions and mockable interfaces
- `apps/MacFanControlHelper`: macOS helper tool scaffold for future privileged separation
- `docs/ARCHITECTURE.md`: system design notes

## Suggested next steps

1. Create an Xcode workspace and add the four local packages.
2. Build the macOS menu bar app around `ControlCore` and `SMCBridge`.
3. Add an iPhone SwiftUI app that consumes `RemoteProtocol`.
4. Replace the mock SMC bridge with a real Intel SMC implementation once the
   low-level prototype is validated on hardware.

## Bootstrapping

- If you use XcodeGen, run `xcodegen generate` from the repository root.
- Open the generated project and ensure the local package references resolve.
- Start by running the preview-backed app shells before wiring real SMC access.
- The iPhone app now defaults to a live `Network.framework` discovery path and
  expects a Mac host advertising `LocalTransport.bonjourServiceType` on the
  local network.
- `AppleSMCTransport` is intentionally still a safe skeleton. The remaining work
  is the real IOKit call path, key validation, and privileged helper strategy.
- Set `MFC_USE_INTEL_SMC=1` in the macOS app scheme environment to force the
  Intel runtime path instead of the preview mock runtime.
- Set `MFC_USE_HELPER_PROCESS=1` to make the macOS app talk to the separate
  `MacFanControlHelper` process instead of the in-process helper.
- Use `MFC_HELPER_PATH` when you want the app to launch a specific helper
  executable during local development.
