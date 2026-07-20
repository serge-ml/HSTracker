//
//  HearthArenaPreferencesMigrator.swift
//  HSTracker
//

import AppKit

enum HearthArenaPreferencesMigrator {
    private static let completedKey = "heartharena.preferences_migration_completed"
    private static let legacyDomains = [
        "net.hearthsim.hstracker",
        "be.michotte.hstracker"
    ]

    private static let allowedKeys = [
        Settings.hearthstone_log_path,
        Settings.hearthstone_language,
        Settings.hstracker_language,
        Settings.can_join_fullscreen,
        Settings.quit_when_hs_closes,
        Settings.card_size,
        Settings.rarity_colors,
        Settings.auto_position_trackers,
        Settings.hide_all_trackers_when_not_in_game,
        Settings.hide_all_trackers_when_game_in_background,
        Settings.window_locked,
        Settings.prefer_golden_cards,
        Settings.auto_deck_detection,
        Settings.archive_arena_deck,
        Settings.save_replays,
        Settings.theme_token
    ]

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: completedKey) else {
            return
        }
        guard let legacy = firstLegacyDomain() else {
            defaults.set(true, forKey: completedKey)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Import settings from HSTracker?"
        alert.informativeText =
            "HSTracker Arena can copy known local settings from the official app. " +
            "HSReplay login tokens will not be copied, and the old preferences will not be deleted."
        alert.addButton(withTitle: "Import Settings")
        alert.addButton(withTitle: "Skip")

        if alert.runModal() == .alertFirstButtonReturn {
            for key in allowedKeys where defaults.object(forKey: key) == nil {
                if let value = legacy[key] {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.synchronize()
        }
        defaults.set(true, forKey: completedKey)
    }

    private static func firstLegacyDomain() -> [String: Any]? {
        for domain in legacyDomains {
            if let values = UserDefaults.standard.persistentDomain(forName: domain),
               !values.isEmpty {
                return values
            }
        }
        return nil
    }
}
