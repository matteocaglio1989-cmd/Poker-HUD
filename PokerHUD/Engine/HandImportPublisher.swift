import Foundation
import Combine

/// Combine bus that `ImportEngine` publishes to after every successful
/// `importFileForHUD` call, and that `HUDManager` subscribes to so it can
/// refresh stat panels without `AppState` having to wire the two directly.
///
/// There is exactly one instance per `AppState`, constructed in its `init`
/// and injected into both `ImportEngine` and `HUDManager`. Do not construct
/// additional instances — the whole point is a single shared bus. Prior Phase
/// 2 work (`3534c8b`) showed that dual-instance wiring creates subtle state
/// drift (`lastSavedOrigin` drift bug), so we centralize here.
final class HandImportPublisher {
    /// Fires once per successful `importFileForHUD` call. Subscribers should
    /// expect to receive this on an arbitrary queue and hop back to the main
    /// actor themselves if they touch UI state.
    let handsImported = PassthroughSubject<HUDImportResult, Never>()

    init() {}

    /// Publish a result. Called by `ImportEngine` at the end of a successful
    /// HUD import. No-op if `result.handsImported == 0` — we only notify when
    /// there is actually something new to reflect in the HUD.
    func publish(_ result: HUDImportResult) {
        guard result.handsImported > 0 else { return }
        handsImported.send(result)
    }
}
