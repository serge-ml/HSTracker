//
//  HSReplayArenaHeroOverlayController.swift
//  HSTracker
//

import AppKit

final class HSReplayArenaHeroOverlayController {
    private let panel: HSReplayArenaOverlayWindow
    private let contentView = NSView(frame: .zero)
    private let badges = (0..<3).map {
        _ in HSReplayArenaHeroRatingView(frame: .zero)
    }
    private var observers = [NSObjectProtocol]()
    private var positionTimer: Timer?
    private var currentOffer: HSReplayArenaRatedHeroOffer?
    private var hearthstoneIsActive = CoreManager.isHearthstoneActive()
    private var lastPresentationSignature: String?

    init() {
        panel = HSReplayArenaOverlayWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configurePanel()
        observeLifecycle()
        startPositionMonitoring()
    }

    deinit {
        positionTimer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show(_ offer: HSReplayArenaRatedHeroOffer) {
        onMain { [weak self] in
            self?.currentOffer = offer
            self?.renderIfAllowed()
        }
    }

    func hide(clearOffer: Bool = true) {
        onMain { [weak self] in
            guard let self = self else { return }
            if clearOffer {
                self.currentOffer = nil
            }
            self.panel.orderOut(nil)
        }
    }

    private func configurePanel() {
        panel.contentView = contentView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 1
        )
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        for badge in badges {
            contentView.addSubview(badge)
        }
        panel.orderOut(nil)
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        let names = [
            Events.hearthstone_active,
            Events.hearthstone_deactived,
            Events.hearthstone_closed,
            Events.space_changed,
            HSReplayArenaSettings.enabledKey,
            HSReplayArenaSettings.showRankKey,
            HSReplayArenaSettings.overlayScaleKey,
            HSReplayArenaSettings.verticalOffsetKey,
            HSReplayArenaSettings.hideWhenBackgroundKey,
            Settings.can_join_fullscreen
        ]

        for name in names {
            let observer = center.addObserver(
                forName: Notification.Name(rawValue: name),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handle(notification: notification)
            }
            observers.append(observer)
        }
    }

    private func startPositionMonitoring() {
        let timer = Timer(timeInterval: 1, repeats: true) {
            [weak self] _ in
            guard self?.currentOffer != nil else { return }
            self?.renderIfAllowed()
        }
        RunLoop.main.add(timer, forMode: .common)
        positionTimer = timer
    }

    private func handle(notification: Notification) {
        switch notification.name.rawValue {
        case Events.hearthstone_active:
            hearthstoneIsActive = true
            renderIfAllowed()
        case Events.hearthstone_deactived:
            hearthstoneIsActive = false
            if HSReplayArenaSettings.hideWhenHearthstoneIsInBackground {
                panel.orderOut(nil)
            }
        case Events.hearthstone_closed:
            hearthstoneIsActive = false
            hide()
        default:
            renderIfAllowed()
        }
    }

    private func renderIfAllowed() {
        hearthstoneIsActive = CoreManager.isHearthstoneActive()

        guard HSReplayArenaSettings.enabled else {
            logPresentation("hidden disabled")
            panel.orderOut(nil)
            return
        }
        guard
            !HSReplayArenaSettings.hideWhenHearthstoneIsInBackground ||
                hearthstoneIsActive
        else {
            logPresentation("hidden hearthstone-in-background")
            panel.orderOut(nil)
            return
        }
        guard let offer = currentOffer, offer.heroes.count == 3 else {
            logPresentation("hidden no-three-hero-offer")
            panel.orderOut(nil)
            return
        }

        SizeHelper.hearthstoneWindow.reload()
        let frame = SizeHelper.hearthstoneWindow.frame
        guard frame.width > 0, frame.height > 0 else {
            logPresentation("hidden invalid-hearthstone-frame \(frame)")
            panel.orderOut(nil)
            return
        }

        panel.collectionBehavior = Settings.canJoinFullscreen
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : []
        panel.setFrame(frame, display: true, animate: false)

        let badgeFrames = HSReplayArenaOverlayLayout.heroBadgeFrames(
            in: frame.size,
            scale: CGFloat(HSReplayArenaSettings.overlayScale),
            verticalOffset: CGFloat(
                HSReplayArenaSettings.verticalOffset
            )
        )
        guard badgeFrames.count == badges.count else {
            logPresentation("hidden invalid-badge-layout")
            panel.orderOut(nil)
            return
        }

        for index in badges.indices {
            badges[index].frame = badgeFrames[index]
            badges[index].update(
                with: offer.heroes[index],
                showRank: HSReplayArenaSettings.showRank
            )
        }
        let classes = offer.heroes
            .map { $0.hero.heroClass.rawValue }
            .joined(separator: ",")
        logPresentation(
            "visible frame=\(frame) classes=[\(classes)]"
        )
        panel.orderFrontRegardless()
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func logPresentation(_ signature: String) {
        guard signature != lastPresentationSignature else { return }
        lastPresentationSignature = signature
        logger.info("Arena class stats overlay \(signature)")
    }
}

private final class HSReplayArenaOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
