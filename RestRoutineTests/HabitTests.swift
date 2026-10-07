import XCTest
@testable import RestRoutine

final class HabitTests: XCTestCase {
    let locale = Locale(identifier: "en_US")

    func testBlankWaterIsNotLoggedButZeroIsRecorded() throws {
        XCTAssertNil(try HabitParsing.water("", unit: .milliliters, locale: locale))
        XCTAssertEqual(try HabitParsing.water("0", unit: .milliliters, locale: locale), 0)
        XCTAssertEqual(try HabitParsing.water("1,000", unit: .milliliters, locale: locale), 1000)
    }

    func testWaterRejectsInvalidValues() {
        for text in ["-5", "abc", "inf", "nan"] {
            XCTAssertThrowsError(try HabitParsing.water(text, unit: .milliliters, locale: locale), text)
        }
    }

    func testWaterStoresMillilitersFromFluidOunces() throws {
        let ml = try XCTUnwrap(HabitParsing.water("8", unit: .usFluidOunces, locale: locale))
        XCTAssertEqual(ml, 236.588, accuracy: 0.001)
        XCTAssertEqual(WaterUnit.usFluidOunces.format(milliliters: ml), "8 fl oz")
        XCTAssertEqual(WaterUnit.milliliters.format(milliliters: 1000), "1,000 mL")
    }

    func testMovementAcceptsWholeNonnegativeMinutesOnly() throws {
        XCTAssertNil(try HabitParsing.movement(""))
        XCTAssertEqual(try HabitParsing.movement("0"), 0)
        XCTAssertEqual(try HabitParsing.movement("20"), 20)
        XCTAssertThrowsError(try HabitParsing.movement("12.5")) {
            XCTAssertEqual($0 as? HabitValidationError, .movementNotWholeNumber)
        }
        XCTAssertThrowsError(try HabitParsing.movement("-3")) {
            XCTAssertEqual($0 as? HabitValidationError, .movementNegative)
        }
    }

    func testMissingValuesDisplayAsNotLogged() {
        XCTAssertEqual(Display.water(nil, unit: .milliliters), "Not logged")
        XCTAssertEqual(Display.water(0, unit: .milliliters), "0 mL")
        XCTAssertEqual(Display.movement(nil), "Not logged")
        XCTAssertEqual(Display.movement(0), "0 min")
        XCTAssertEqual(Display.windDown(nil), "Not logged")
        XCTAssertEqual(Display.windDown(.notDone), "Not done")
    }
}
