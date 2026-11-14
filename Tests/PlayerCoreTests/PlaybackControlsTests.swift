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

import Testing
@testable import PlayerCore

@Test func fullscreenControlsHideOnlyAfterThreeIdleSeconds() {
    var policy = PlaybackControlsPolicy()
    policy.setFullscreen(true, at: 10)
    policy.evaluate(at: 12.99, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
    policy.evaluate(at: 13, canHide: true, interactionHeld: false)
    #expect(policy.hidden)
}

@Test func keyboardOrPointerActivityRevealsAndRestartsIdleDelay() {
    var policy = PlaybackControlsPolicy()
    policy.setFullscreen(true, at: 0)
    policy.evaluate(at: 4, canHide: true, interactionHeld: false)
    #expect(policy.hidden)
    policy.activity(at: 4)
    #expect(!policy.hidden)
    policy.evaluate(at: 6.9, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
    policy.evaluate(at: 7, canHide: true, interactionHeld: false)
    #expect(policy.hidden)
}

@Test func pausesBufferingErrorsAndAudioOnlyKeepControlsVisible() {
    var policy = PlaybackControlsPolicy()
    policy.setFullscreen(true, at: 0)
    policy.evaluate(at: 5, canHide: true, interactionHeld: false)
    policy.evaluate(at: 6, canHide: false, interactionHeld: false)
    #expect(!policy.hidden)
    policy.evaluate(at: 100, canHide: false, interactionHeld: false)
    policy.evaluate(at: 102.9, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
}

@Test func activeControlsMenusAndFocusPinChromeUntilInteractionEnds() {
    var policy = PlaybackControlsPolicy()
    policy.setFullscreen(true, at: 0)
    policy.evaluate(at: 20, canHide: true, interactionHeld: true)
    #expect(!policy.hidden)
    policy.evaluate(at: 22.9, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
    policy.evaluate(at: 23, canHide: true, interactionHeld: false)
    #expect(policy.hidden)
}

@Test func windowedModeAndLeavingFullscreenAlwaysRestoreChrome() {
    var policy = PlaybackControlsPolicy()
    policy.evaluate(at: 100, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
    policy.setFullscreen(true, at: 100)
    policy.evaluate(at: 104, canHide: true, interactionHeld: false)
    #expect(policy.hidden)
    policy.setFullscreen(false, at: 105)
    #expect(!policy.hidden && !policy.fullscreen)
    policy.evaluate(at: 1_000, canHide: true, interactionHeld: false)
    #expect(!policy.hidden)
}
