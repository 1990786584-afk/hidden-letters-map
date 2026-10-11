import Foundation
import CoreLocation
import UserNotifications
import SwiftUI

// Those Letters We Passed By ♡
// OS-managed geofences, never continuous background GPS or location-history upload.
// Only an explicit opt-in enables monitoring. Consent and discovered IDs live on-device.
@MainActor
final class LetterGeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate, UNUserNotificationCenterDelegate {
    @Published private(set) var enabled: Bool
    @Published private(set) var statusMessage = "默认关闭 · 你可以随时选择开启"
    @Published var requestedLetterID: String?

    private let manager = CLLocationManager()
    private let prefix = "zfxf.letter."
    private let maxActive = 19 // iOS permits at most 20 regions per app.
    private let enabledKey = "zfxf.geofence.enabled"
    private let pendingKey = "zfxf.geofence.pending"
    private let notifiedKey = "zfxf.geofence.notified"
    private var api: LoveMapAPI?
    private var syncing = false
    private var lastKnownLocation: CLLocation?
    private var requestedAlwaysPermissionThisSession = false

    override init() {
        enabled = UserDefaults.standard.bool(forKey: "zfxf.geofence.enabled")
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        UNUserNotificationCenter.current().delegate = self
        if !enabled {
            stopAllRegions()
        }
    }

    var permissionDetail: String {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return "已允许后台定位 · iPhone 会在你接近藏宝点时尝试通知（不保证实时）"
        case .authorizedWhenInUse:
            return "目前仅允许使用期间定位。后台提醒需要在系统定位权限中选择「始终」。"
        case .notDetermined:
            return "还没有定位授权。启用后会向你分别申请通知和后台定位权限。"
        case .denied, .restricted:
            return "定位未授权。请到 iPhone 设置 → ZFxF → 位置，打开「始终允许」。"
        @unknown default:
            return "定位权限状态暂时未知。"
        }
    }

    // Called only after a user taps an explicit enable button.
    func enableWithConsent(api: LoveMapAPI?) async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else {
            statusMessage = "通知权限被拒绝。请先在系统设置中允许 ZFxF 发送通知。"
            return
        }
        enabled = true
        UserDefaults.standard.set(true, forKey: enabledKey)
        self.api = api
        if manager.authorizationStatus != .authorizedAlways {
            statusMessage = "请在 iPhone 系统定位权限中允许「始终」，才能在后台经过时提醒。"
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                requestedAlwaysPermissionThisSession = true
                manager.requestAlwaysAuthorization()
            }
        }
        await refreshIfEnabled(api: api)
    }

    func disable() {
        enabled = false
        UserDefaults.standard.set(false, forKey: enabledKey)
        stopAllRegions()
        statusMessage = "已关闭后台发现；此前发现的来信仍然保留。"
    }

    // Re-sync on app activation and when the user visits Settings.
    // Newly hidden letters are not automatically synchronized while this app
    // stays closed for days: a future APNs refresh would be needed for that.
    func refreshIfEnabled(api: LoveMapAPI?) async {
        self.api = api
        guard enabled else { stopAllRegions(); return }
        guard manager.authorizationStatus == .authorizedAlways else {
            stopAllRegions()
            statusMessage = permissionDetail
            return
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              manager.maximumRegionMonitoringDistance > 0 else {
            stopAllRegions()
            statusMessage = "此设备当前不支持地理围栏监测。"
            return
        }
        guard let api else {
            statusMessage = "等待你解锁 iPhone，才能同步待发现的来信。"
            return
        }
        await flushPending()
        do {
            let zones = try await api.geofenceRegions()
            let here = lastKnownLocation ?? manager.location
            let chosen = Array(zones.sorted { left, right in
                guard let here else { return left.id < right.id }
                return left.location.distance(from: here) < right.location.distance(from: here)
            }.prefix(maxActive))

            let wantedIDs = Set(chosen.map { prefix + $0.id })
            for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix)
                && !wantedIDs.contains(region.identifier) {
                manager.stopMonitoring(for: region)
            }

            for zone in chosen {
                let id = prefix + zone.id
                let existing = manager.monitoredRegions.first(where: { $0.identifier == id }) as? CLCircularRegion
                if let existing {
                    if abs(existing.center.latitude - zone.lat) < 0.00001 &&
                       abs(existing.center.longitude - zone.lon) < 0.00001 &&
                       abs(existing.radius - zone.radiusM) < 1 {
                        continue
                    }
                    manager.stopMonitoring(for: existing)
                }
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(latitude: zone.lat, longitude: zone.lon),
                    radius: min(zone.radiusM, manager.maximumRegionMonitoringDistance),
                    identifier: id
                )
                region.notifyOnEntry = true
                region.notifyOnExit = false
                manager.startMonitoring(for: region)
                // When first enabled *inside* an existing letter's circle, the
                // user should not need to exit and walk back in to discover it.
                manager.requestState(for: region)
            }
            statusMessage = chosen.isEmpty
                ? "已开启 ♡ 目前没有等待发现的普通来信。"
                : "正在留意附近的 \(chosen.count) 封信。经过时可能延迟通知；信不会自动拆开。"
        } catch {
            statusMessage = "同步藏宝点失败；稍后打开 App 会再试：\(error.localizedDescription)"
        }
    }

    private func stopAllRegions() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(prefix) {
            manager.stopMonitoring(for: region)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Initial "When In Use" request must complete before upgrading to Always.
        if enabled && manager.authorizationStatus == .authorizedWhenInUse &&
            !requestedAlwaysPermissionThisSession {
            requestedAlwaysPermissionThisSession = true
            manager.requestAlwaysAuthorization()
        }
        Task { await refreshIfEnabled(api: api) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let current = locations.last { lastKnownLocation = current }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        statusMessage = "附近来信监测失败：\(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        receiveEntry(region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside { receiveEntry(region) }
    }

    private func receiveEntry(_ region: CLRegion) {
        guard enabled, manager.authorizationStatus == .authorizedAlways,
              region.identifier.hasPrefix(prefix) else { return }
        let letterID = String(region.identifier.dropFirst(prefix.count))
        var notified = Set(UserDefaults.standard.stringArray(forKey: notifiedKey) ?? [])
        if !notified.insert(letterID).inserted { return }
        UserDefaults.standard.set(Array(notified), forKey: notifiedKey)

        var pending = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
        pending.insert(letterID)
        UserDefaults.standard.set(Array(pending), forKey: pendingKey)

        let content = UNMutableNotificationContent()
        content.title = "💌 那些与你擦肩而过的信"
        content.body = "宝宝，你刚刚经过了一个藏着秘密的地方。有封信会一直等你，有空再亲手拆开 ♡"
        content.sound = .default
        content.userInfo = ["letterID": letterID]
        let request = UNNotificationRequest(
            identifier: "zfxf.found.\(letterID)", content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        // The local alert can appear without a network request. The event ID is
        // durably queued for server reconciliation after unlock/next app launch.
        Task { await flushPending() }
    }

    func flushPending() async {
        guard !syncing, let api else { return }
        syncing = true
        defer { syncing = false }
        let pending = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        for id in pending {
            do {
                let response = try await api.discoverViaGeofence(id)
                if response.ok, response.status == "found" || response.status == "opened" {
                    var remaining = Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
                    remaining.remove(id)
                    UserDefaults.standard.set(Array(remaining), forKey: pendingKey)
                }
            } catch {
                // Keychain may be unavailable while iPhone is locked. Keep queued
                // IDs and retry when the app next comes to the foreground.
            }
        }
    }

    // Show a banner even when ZFxF is already open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let letterID = response.notification.request.content.userInfo["letterID"] as? String
        // Never keep iOS waiting for network before completing notification tap.
        completionHandler()
        Task { @MainActor in
            await self.flushPending()
            self.requestedLetterID = letterID
        }
    }
}
