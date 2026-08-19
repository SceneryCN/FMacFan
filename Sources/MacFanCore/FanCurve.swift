import Foundation

public struct FanCurve: Equatable, Sendable {
    private let points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.temperature < $1.temperature }
    }

    public func speedFraction(at temperature: Double) -> Double {
        guard let first: CurvePoint = points.first,
              let last: CurvePoint = points.last else {
            return 0
        }
        guard temperature > first.temperature else {
            return clamped(first.speedFraction)
        }
        guard temperature < last.temperature else {
            return clamped(last.speedFraction)
        }

        for (lower, upper) in zip(points, points.dropFirst())
        where temperature <= upper.temperature {
            let temperatureSpan: Double = upper.temperature - lower.temperature
            guard temperatureSpan > 0 else {
                return clamped(upper.speedFraction)
            }
            let progress: Double = (temperature - lower.temperature) / temperatureSpan
            let interpolated: Double = lower.speedFraction
                + ((upper.speedFraction - lower.speedFraction) * progress)
            return clamped(interpolated)
        }

        return clamped(last.speedFraction)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
