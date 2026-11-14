// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
// Copyright (C) 2026 Ali Ahad <https://aliahad.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import AppKit
import Observation
import SwiftUI
import PlayerCore

@Observable final class FullscreenControls {
    private(set) var active = false
    private(set) var visible = true
    private(set) var transitioning = false
    var topHeight = 100.0
    var bottomHeight = 120.0
    var canHide: (() -> Bool)?
    var onExit: (() -> Void)?
    @ObservationIgnored private var policy = PlaybackControlsPolicy()
    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var eventMonitor: Any?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var originalToolbarVisible = true
    @ObservationIgnored private var originalMouseMoved = false
    @ObservationIgnored private var menuDepth = 0
    @ObservationIgnored private var scrubbing = false
    @ObservationIgnored private var keyboardNavigation = false
    @ObservationIgnored private var cursorHidden = false
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func enter(_ window: NSWindow) {
        guard !active else { return }
        self.window = window
        originalToolbarVisible = window.toolbar?.isVisible ?? false
        originalMouseMoved = window.acceptsMouseMovedEvents
        window.toolbar?.isVisible = false
        window.acceptsMouseMovedEvents = true
        transitioning = true; active = true
        policy.setFullscreen(true, at: now); applyVisibility()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .scrollWheel, .keyDown, .flagsChanged]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .keyDown && event.keyCode == 48 { self.keyboardNavigation = true }
            if [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { self.keyboardNavigation = false }
            self.reveal()
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuDepth += 1; self?.reveal() }
        })
        observers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { self.menuDepth = max(0, self.menuDepth - 1); self.reveal() } }
        })
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 0.05
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func entered() { transitioning = false; reveal() }
    func willExit() { transitioning = true; reveal() }
    func exit() {
        timer?.invalidate(); timer = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        if let window {
            window.toolbar?.isVisible = originalToolbarVisible
            window.acceptsMouseMovedEvents = originalMouseMoved
        }
        self.window = nil
        active = false; transitioning = false; menuDepth = 0; scrubbing = false; keyboardNavigation = false
        policy.setFullscreen(false, at: now); applyVisibility(); onExit?()
    }
    func reveal() { policy.activity(at: now); applyVisibility() }
    func setScrubbing(_ value: Bool) { guard active else { return }; scrubbing = value; reveal() }
    func pointerIsOverControls(_ mouse: NSPoint) -> Bool {
        guard let window else { return false }
        return mouse.x >= 0 && mouse.x <= window.frame.width && mouse.y >= 0 && mouse.y <= window.frame.height && (mouse.y <= bottomHeight || mouse.y >= window.frame.height - topHeight)
    }
    func evaluate() {
        guard active, let window else { return }
        let mouse = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let atEdge = pointerIsOverControls(mouse)
        let editing = window.firstResponder is NSTextView
        let held = transitioning || atEdge || scrubbing || menuDepth > 0 || keyboardNavigation || editing || NSEvent.pressedMouseButtons != 0 || !window.isKeyWindow || !NSApp.isActive || window.attachedSheet != nil || NSApp.modalWindow != nil || NSWorkspace.shared.isVoiceOverEnabled
        policy.evaluate(at: now, canHide: canHide?() == true, interactionHeld: held)
        applyVisibility()
    }
    private func applyVisibility() {
        let show = !policy.hidden
        if visible != show {
            if !show && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.125)) { visible = false }
            } else {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { visible = show }
            }
        }
        if !show && !cursorHidden {
            NSCursor.setHiddenUntilMouseMoves(true); cursorHidden = true
        } else if show && cursorHidden {
            NSCursor.setHiddenUntilMouseMoves(false); cursorHidden = false
        }
    }
}
