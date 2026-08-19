import MacFanCore
import XCTest

final class FanCurveTests: XCTestCase {
    func testInterpolatesBetweenPoints() {
        let curve: FanCurve = FanCurve(points: [
            CurvePoint(temperature: 40, speedFraction: 0.2),
            CurvePoint(temperature: 80, speedFraction: 1),
        ])

        XCTAssertEqual(curve.speedFraction(at: 60), 0.6, accuracy: 0.0001)
    }

    func testClampsOutsideCurveRange() {
        let curve: FanCurve = FanCurve(points: [
            CurvePoint(temperature: 40, speedFraction: 0.2),
            CurvePoint(temperature: 80, speedFraction: 0.8),
        ])

        XCTAssertEqual(curve.speedFraction(at: 20), 0.2)
        XCTAssertEqual(curve.speedFraction(at: 100), 0.8)
    }

    func testSortsUnorderedPoints() {
        let curve: FanCurve = FanCurve(points: [
            CurvePoint(temperature: 80, speedFraction: 1),
            CurvePoint(temperature: 40, speedFraction: 0),
        ])

        XCTAssertEqual(curve.speedFraction(at: 60), 0.5, accuracy: 0.0001)
    }

    func testDecodesAppleSiliconFloat() throws {
        var bits: UInt32 = Float(55.5).bitPattern.littleEndian
        let bytes: [UInt8] = withUnsafeBytes(of: &bits) { Array($0) }
        let value: SMCValue = SMCValue(dataType: "flt ", bytes: bytes)

        XCTAssertEqual(try value.doubleValue(), 55.5, accuracy: 0.001)
    }

    func testDecodesSP78Temperature() throws {
        let value: SMCValue = SMCValue(
            dataType: "sp78",
            bytes: [0x37, 0x80]
        )

        XCTAssertEqual(try value.doubleValue(), 55.5, accuracy: 0.001)
    }
}
