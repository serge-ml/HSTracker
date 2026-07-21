//
//  HSReplayArenaSettings.swift
//  HSTracker
//

import Foundation

enum HSReplayArenaSettings {
    static let enabledKey = "hsreplay_arena.enabled"
    static let showRankKey = "hsreplay_arena.show_rank"
    static let overlayScaleKey = "hsreplay_arena.overlay_scale"
    static let verticalOffsetKey = "hsreplay_arena.vertical_offset"
    static let hideWhenBackgroundKey =
        "hsreplay_arena.hide_when_background"

    private static let defaults = UserDefaults.standard

    static var enabled: Bool {
        get { bool(forKey: enabledKey, defaultValue: true) }
        set { set(newValue, forKey: enabledKey) }
    }

    static var showRank: Bool {
        get { bool(forKey: showRankKey, defaultValue: true) }
        set { set(newValue, forKey: showRankKey) }
    }

    static var overlayScale: Double {
        get {
            guard defaults.object(forKey: overlayScaleKey) != nil else {
                return 1
            }
            return min(
                max(defaults.double(forKey: overlayScaleKey), 0.75),
                1.5
            )
        }
        set {
            set(
                min(max(newValue, 0.75), 1.5),
                forKey: overlayScaleKey
            )
        }
    }

    static var verticalOffset: Double {
        get {
            guard defaults.object(forKey: verticalOffsetKey) != nil else {
                return 0
            }
            return min(
                max(defaults.double(forKey: verticalOffsetKey), -200),
                200
            )
        }
        set {
            set(
                min(max(newValue, -200), 200),
                forKey: verticalOffsetKey
            )
        }
    }

    static var hideWhenHearthstoneIsInBackground: Bool {
        get { bool(forKey: hideWhenBackgroundKey, defaultValue: true) }
        set { set(newValue, forKey: hideWhenBackgroundKey) }
    }

    static func resetOverlayPosition() {
        overlayScale = 1
        verticalOffset = 0
    }

    private static func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }

    private static func set(_ value: Any, forKey key: String) {
        defaults.set(value, forKey: key)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name(rawValue: key),
                object: value
            )
        }
    }
}
