import AppKit
import Foundation
import Testing

@testable import Glint

struct ScrollNavigationTests {
  @Test func offDisablesBothKindsOfScrollingAndWheelOnlyIgnoresPreciseEvents() {
    var navigation = ScrollNavigation()
    #expect(navigation.offset(for: .init(deltaY: -1), mode: .off) == nil)
    #expect(navigation.offset(for: .init(deltaY: -100, precise: true), mode: .off) == nil)
    #expect(navigation.offset(for: .init(deltaY: -100, precise: true), mode: .wheelOnly) == nil)
    #expect(navigation.offset(for: .init(deltaY: -1), mode: .wheelOnly) == 1)
  }

  @Test func singleLineWheelTicksBrowseWithoutDroppingRapidTicks() {
    var navigation = ScrollNavigation()
    #expect(navigation.offset(for: .init(deltaY: -1, timestamp: 1), mode: .wheelOnly) == 1)
    #expect(navigation.offset(for: .init(deltaY: -1, timestamp: 1.01), mode: .wheelOnly) == 1)
    #expect(navigation.offset(for: .init(deltaY: 1, timestamp: 1.02), mode: .wheelOnly) == -1)
    #expect(navigation.offset(for: .init(deltaY: -8), mode: .wheelAndTrackpad) == 1)
    #expect(navigation.offset(for: .init(deltaY: 0), mode: .wheelOnly) == nil)
    #expect(navigation.offset(for: .init(deltaX: 3, deltaY: -1), mode: .wheelOnly) == nil)
  }

  @Test func trackpadRequiresDeliberateMovementAndOnlyNavigatesOncePerGesture() {
    var navigation = ScrollNavigation()
    #expect(
      navigation.offset(
        for: .init(deltaY: -10, precise: true, phase: .began), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: -10, precise: true, phase: .changed), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: -15, precise: true, phase: .changed), mode: .wheelAndTrackpad) == 1)
    #expect(
      navigation.offset(
        for: .init(deltaY: -100, precise: true, phase: .changed), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: 100, precise: true, phase: .changed), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: 0, precise: true, phase: .ended), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: 40, precise: true, phase: .began), mode: .wheelAndTrackpad) == -1)
  }

  @Test func momentumNeverBrowsesEvenAfterAGestureEnds() {
    var navigation = ScrollNavigation()
    for phase: NSEvent.Phase in [.began, .changed, .ended] {
      #expect(
        navigation.offset(
          for: .init(deltaY: -100, precise: true, momentumPhase: phase),
          mode: .wheelAndTrackpad) == nil)
    }
    #expect(
      navigation.offset(
        for: .init(deltaY: -40, precise: true, phase: .began), mode: .wheelAndTrackpad) == 1)
  }

  @Test func horizontalGesturesAndDirectionChangesDoNotAccumulateAccidentalNavigation() {
    var navigation = ScrollNavigation()
    #expect(
      navigation.offset(
        for: .init(deltaX: 100, deltaY: -40, precise: true, phase: .began),
        mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: -20, precise: true, phase: .changed), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: 20, precise: true, phase: .changed), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: 15, precise: true, phase: .changed), mode: .wheelAndTrackpad) == -1)
    #expect(
      navigation.offset(
        for: .init(deltaY: 0, precise: true, phase: .cancelled), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: -40, precise: true, phase: .began), mode: .wheelAndTrackpad) == 1)
  }

  @Test func smoothMiceWithoutGesturePhasesUseSeparateScrollBursts() {
    var navigation = ScrollNavigation()
    #expect(
      navigation.offset(
        for: .init(deltaY: -40, precise: true, timestamp: 1), mode: .wheelAndTrackpad) == 1)
    #expect(
      navigation.offset(
        for: .init(deltaY: -40, precise: true, timestamp: 1.1), mode: .wheelAndTrackpad) == nil)
    #expect(
      navigation.offset(
        for: .init(deltaY: -40, precise: true, timestamp: 1.5), mode: .wheelAndTrackpad) == 1)
  }

  @Test @MainActor func scrollModeDefaultsOffAndPersistsEachChoice() throws {
    let suite = "GlintScrollPreferences-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.scrollNavigation == .off)
    for mode in ScrollNavigationMode.allCases {
      preferences.scrollNavigation = mode
      #expect(Preferences(defaults: defaults).scrollNavigation == mode)
    }
  }

  @Test @MainActor func oldScrollPreferenceMigratesWithoutOverridingANewChoice() throws {
    let suite = "GlintScrollMigration-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "scrollToBrowse")
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.scrollNavigation == .wheelAndTrackpad)
    preferences.scrollNavigation = .off
    #expect(Preferences(defaults: defaults).scrollNavigation == .off)
  }
}
