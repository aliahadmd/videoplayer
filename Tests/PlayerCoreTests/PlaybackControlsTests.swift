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
