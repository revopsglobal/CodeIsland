import AppKit
import Carbon.HIToolbox
import XCTest
@testable import CodeIsland

final class GlobalHotKeyManagerTests: XCTestCase {
    func testCarbonModifiersMapsCommandShift() {
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods, UInt32(cmdKey) | UInt32(shiftKey))
    }

    func testCarbonModifiersMapsAllFourFlags() {
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift, .option, .control])
        XCTAssertEqual(mods, UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testCarbonModifiersEmptyForNoFlags() {
        XCTAssertEqual(GlobalHotKeyManager.carbonModifiers(from: []), 0)
    }

    func testCarbonModifiersIgnoresNonModifierFlags() {
        // Caps lock / numeric pad etc. must not contribute to the Carbon mask.
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .capsLock])
        XCTAssertEqual(mods, UInt32(cmdKey))
    }

    func testQuickJotDefaultsUseControlOptionTAndN() throws {
        let task = try XCTUnwrap(ShortcutAction.quickTask.defaultBinding)
        let note = try XCTUnwrap(ShortcutAction.quickNote.defaultBinding)

        XCTAssertEqual(task.keyCode, UInt16(kVK_ANSI_T))
        XCTAssertEqual(note.keyCode, UInt16(kVK_ANSI_N))
        XCTAssertEqual(task.modifiers, [.control, .option])
        XCTAssertEqual(note.modifiers, [.control, .option])
        XCTAssertTrue(ShortcutAction.quickTask.defaultEnabled)
        XCTAssertTrue(ShortcutAction.quickNote.defaultEnabled)
    }

    func testDefaultShortcutRegistrationsAreConflictFree() {
        let bindings = ShortcutAction.allCases.compactMap(\.defaultBinding)

        XCTAssertTrue(GlobalHotKeyManager.hasUniqueChords(bindings))
    }
}
