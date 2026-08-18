import SwiftUI

extension AppState {
    func setZoomLevel(_ level: CGFloat, animated: Bool = true) {
        let clamped = min(ZoomConstants.max, max(ZoomConstants.min, level))
        guard clamped != zoomLevel else { return }
        if animated {
            withAnimation(.smooth(duration: 0.3)) {
                zoomLevel = clamped
            }
        } else {
            zoomLevel = clamped
        }
        zoomPersistTask?.cancel()
        let task = DispatchWorkItem {
            UserDefaults.standard.set(clamped, forKey: "lastZoomLevel")
        }
        zoomPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    /// Pinch/scroll-wheel zoom. Writes at most ~30fps: `zoomLevel` is observed by every visible
    /// row, so a raw per-tick write re-evaluates the whole editor. Call `endContinuousZoom()` when
    /// the gesture finishes so the final value is never dropped.
    func setZoomLevelContinuous(_ level: CGFloat) {
        zoomThrottle.submit { [weak self] in
            self?.setZoomLevel(level, animated: false)
        }
    }

    func endContinuousZoom() {
        zoomThrottle.flush()
        zoomThrottle.reset()
    }

    func zoomIn() {
        setZoomLevel(zoomLevel + ZoomConstants.step)
    }

    func zoomOut() {
        setZoomLevel(zoomLevel - ZoomConstants.step)
    }

    func resetZoom() {
        let defaultLevel = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        setZoomLevel(defaultLevel > 0 ? defaultLevel : 1.0)
        zoomPersistTask?.cancel()
        UserDefaults.standard.removeObject(forKey: "lastZoomLevel")
    }

    func flushPendingZoomPersist() {
        guard zoomPersistTask != nil else { return }
        zoomPersistTask?.cancel()
        zoomPersistTask = nil
        UserDefaults.standard.set(zoomLevel, forKey: "lastZoomLevel")
    }
}
