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
