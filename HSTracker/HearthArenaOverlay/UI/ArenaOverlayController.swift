//
//  ArenaOverlayController.swift
//  HSTracker
//

import AppKit

final class ArenaOverlayController {
    private let panel: ArenaOverlayWindow
    private let contentView = NSView(frame: .zero)
    private let badges = (0..<5).map { _ in ArenaCardRatingView(frame: .zero) }
    private let packageViews = (0..<3).map {
        _ in ArenaPackageRatingView(frame: .zero)
    }
    private var observers = [NSObjectProtocol]()
    private var positionTimer: Timer?
    private var currentOffer: ArenaRatedOffer?
    private var currentDeckEdit: ArenaRatedDeckEdit?
    private var hearthstoneIsActive = CoreManager.isHearthstoneActive()

    init() {
        panel = ArenaOverlayWindow(
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

    func show(_ offer: ArenaRatedOffer) {
        onMain { [weak self] in
            guard let self = self else { return }
            self.currentOffer = offer
            self.currentDeckEdit = nil
            self.renderIfAllowed()
        }
    }

    func show(_ deckEdit: ArenaRatedDeckEdit) {
        onMain { [weak self] in
            guard let self = self else { return }
            self.currentOffer = nil
            self.currentDeckEdit = deckEdit
            self.renderIfAllowed()
        }
    }

    func hide(clearOffer: Bool = true) {
        onMain { [weak self] in
            guard let self = self else { return }
            if clearOffer {
                self.currentOffer = nil
                self.currentDeckEdit = nil
            }
            self.panel.orderOut(nil)
        }
    }

    func reposition() {
        onMain { [weak self] in
            self?.renderIfAllowed()
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
        for packageView in packageViews {
            contentView.addSubview(packageView)
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
            HearthArenaSettings.enabledKey,
            HearthArenaSettings.showRankKey,
            HearthArenaSettings.useTierColorsKey,
            HearthArenaSettings.overlayScaleKey,
            HearthArenaSettings.verticalOffsetKey,
            HearthArenaSettings.hideWhenBackgroundKey,
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
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard
                self?.currentOffer != nil || self?.currentDeckEdit != nil
            else {
                return
            }
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
            if HearthArenaSettings.hideWhenHearthstoneIsInBackground {
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
        guard
            HearthArenaSettings.enabled,
            !HearthArenaSettings.hideWhenHearthstoneIsInBackground || hearthstoneIsActive
        else {
            panel.orderOut(nil)
            return
        }

        SizeHelper.hearthstoneWindow.reload()
        let frame = SizeHelper.hearthstoneWindow.frame
        guard frame.width > 0, frame.height > 0 else {
            panel.orderOut(nil)
            return
        }

        panel.collectionBehavior = Settings.canJoinFullscreen
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : []
        panel.setFrame(frame, display: true, animate: false)

        if let deckEdit = currentDeckEdit, isRenderable(deckEdit) {
            render(deckEdit, in: frame)
        } else if let offer = currentOffer, isRenderable(offer) {
            render(offer, in: frame)
        } else {
            panel.orderOut(nil)
            return
        }

        panel.orderFront(nil)
    }

    private func render(_ offer: ArenaRatedOffer, in frame: NSRect) {
        if offer.packages.isEmpty {
            for packageView in packageViews {
                packageView.isHidden = true
            }
            let badgeFrames = ArenaOverlayLayout.badgeFrames(
                in: frame.size,
                scale: CGFloat(HearthArenaSettings.overlayScale),
                verticalOffset: CGFloat(HearthArenaSettings.verticalOffset)
            )
            for index in badges.indices {
                guard index < 3 else {
                    badges[index].isHidden = true
                    continue
                }
                badges[index].isHidden = false
                badges[index].frame = badgeFrames[index]
                badges[index].update(
                    with: offer.cards[index],
                    showRank: HearthArenaSettings.showRank,
                    useTierColors: HearthArenaSettings.useTierColors
                )
            }
        } else {
            for badge in badges {
                badge.isHidden = true
            }
            let packageFrames = ArenaOverlayLayout.packageFrames(
                in: frame.size,
                packageCardCounts: offer.packages.map { $0.count },
                scale: CGFloat(HearthArenaSettings.overlayScale),
                verticalOffset: CGFloat(HearthArenaSettings.verticalOffset)
            )
            for index in packageViews.indices {
                packageViews[index].isHidden = false
                packageViews[index].frame = packageFrames[index]
                packageViews[index].update(with: offer.packages[index])
            }
        }
    }

    private func render(_ deckEdit: ArenaRatedDeckEdit, in frame: NSRect) {
        for packageView in packageViews {
            packageView.isHidden = true
        }
        let badgeFrames = ArenaOverlayLayout.redraftBadgeFrames(
            in: frame.size,
            scale: CGFloat(HearthArenaSettings.overlayScale),
            verticalOffset: CGFloat(HearthArenaSettings.verticalOffset)
        )
        for index in badges.indices {
            badges[index].isHidden = false
            badges[index].frame = badgeFrames[index]
            badges[index].update(
                with: deckEdit.discardedCards[index],
                showRank: HearthArenaSettings.showRank,
                useTierColors: HearthArenaSettings.useTierColors
            )
        }

    }

    private func isRenderable(_ offer: ArenaRatedOffer) -> Bool {
        if offer.packages.isEmpty {
            return offer.cards.count == 3
        }
        return offer.packages.count == 3 &&
            offer.packages.allSatisfy { !$0.isEmpty }
    }

    private func isRenderable(_ deckEdit: ArenaRatedDeckEdit) -> Bool {
        deckEdit.discardedCards.count == 5
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }
}
