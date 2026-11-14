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

import Foundation

/// Ephemeral presentation policy. Never changes saved playback or sidebar settings.
public struct PlaybackControlsPolicy: Sendable {
    public static let idleDelay = 3.0
    public private(set) var fullscreen = false
    public private(set) var hidden = false
    private var lastActivity = 0.0
    public init() {}
    public mutating func setFullscreen(_ value: Bool, at time: Double) {
        fullscreen = value; hidden = false; lastActivity = time
    }
    public mutating func activity(at time: Double) {
        hidden = false; lastActivity = time
    }
    public mutating func evaluate(at time: Double, canHide: Bool, interactionHeld: Bool) {
        guard fullscreen && canHide && !interactionHeld else {
            hidden = false; lastActivity = time; return
        }
        hidden = time - lastActivity >= Self.idleDelay
    }
}
