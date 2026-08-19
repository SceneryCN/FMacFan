import AppKit
import MacFanCore
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let snapshot: ThermalSnapshot = model.snapshot,
               !snapshot.fans.isEmpty {
                ScrollView {
                    LazyVStack(spacing: Layout.cardSpacing) {
                        ForEach(snapshot.fans) { fan in
                            FanControlCard(fan: fan, model: model)
                        }
                    }
                    .padding(Layout.contentPadding)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "fan.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("empty.title")
                        .font(.headline)
                    Text("empty.description")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxHeight: .infinity)
            }

            Divider()
            footer
        }
        .frame(width: Layout.width, height: Layout.height)
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "fan")
                .font(.system(size: Layout.headerIconSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Layout.headerIconFrame, height: Layout.headerIconFrame)
                .background(Color.accentColor.gradient)
                .clipShape(RoundedRectangle(cornerRadius: Layout.smallRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text("app.title")
                    .font(.headline)
                Text("app.subtitle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Label(
                LocalizedStringKey(model.status.localizationKey),
                systemImage: model.status == .active
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(model.status == .active ? .green : .orange)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                (model.status == .active ? Color.green : Color.orange)
                    .opacity(0.1)
            )
            .clipShape(Capsule())
        }
        .padding(Layout.contentPadding)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Label("footer.safety", systemImage: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Toggle(
                    "setting.launchAtLogin",
                    isOn: Binding(
                        get: { model.launchAtLoginEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                Button {
                    model.stop()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("action.quit", systemImage: "power")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Layout.contentPadding)
        .padding(.vertical, 10)
    }
}

private struct FanControlCard: View {
    let fan: FanSnapshot
    @ObservedObject var model: AppModel

    private var policy: FanPolicy {
        model.policy(for: fan)
    }

    private var speedFraction: Double {
        guard fan.descriptor.maximumRPM > 0 else {
            return 0
        }
        return min(max(fan.actualRPM / fan.descriptor.maximumRPM, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        LocalizedStringKey(
                            "fan.\(fan.descriptor.side.rawValue).title"
                        )
                    )
                        .font(.headline)
                    HStack(spacing: 4) {
                        metric(value: fan.temperature, unitKey: "unit.celsius")
                        Text("metric.separator")
                        metric(value: fan.actualRPM, unitKey: "unit.rpm")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text(speedFraction, format: .percent)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.gradient)
                        .frame(width: proxy.size.width * speedFraction)
                }
            }
            .frame(height: 4)

            Picker(
                "control.mode",
                selection: Binding(
                    get: { policy.mode },
                    set: { model.setMode($0, fan: fan) }
                )
            ) {
                Text("mode.automatic").tag(FanControlMode.automatic)
                Text("mode.curve").tag(FanControlMode.curve)
                Text("mode.fixed").tag(FanControlMode.fixed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if policy.mode == .fixed {
                speedSlider
            } else if policy.mode == .curve {
                curveEditor
            }
        }
        .padding(Layout.cardPadding)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.84))
        .clipShape(
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var speedSlider: some View {
        VStack(spacing: 6) {
            HStack {
                Text("control.target")
                Spacer()
                Text(policy.fixedSpeedFraction, format: .percent)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(
                value: Binding(
                    get: { policy.fixedSpeedFraction },
                    set: { model.setFixedSpeedFraction($0, fan: fan) }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if !editing {
                        model.commit(fan: fan)
                    }
                }
            )
        }
    }

    private var curveEditor: some View {
        VStack(spacing: 8) {
            ForEach(Array(policy.curve.enumerated()), id: \.offset) { index, point in
                HStack(spacing: 10) {
                    Text(point.temperature, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                    Text("unit.celsius")
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { policy.curve[index].speedFraction },
                            set: {
                                model.setCurveSpeedFraction(
                                    $0,
                                    pointIndex: index,
                                    fan: fan
                                )
                            }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            if !editing {
                                model.commit(fan: fan)
                            }
                        }
                    )
                    Text(policy.curve[index].speedFraction, format: .percent)
                        .frame(width: 38, alignment: .trailing)
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func metric(value: Double?, unitKey: LocalizedStringKey) -> some View {
        if let value {
            Text(value, format: .number.precision(.fractionLength(0)))
            Text(unitKey)
        } else {
            Text("metric.unavailable")
        }
    }
}

private enum Layout {
    static let width: CGFloat = 360
    static let height: CGFloat = 520
    static let contentPadding: CGFloat = 14
    static let cardPadding: CGFloat = 13
    static let cardSpacing: CGFloat = 10
    static let cardRadius: CGFloat = 13
    static let smallRadius: CGFloat = 9
    static let headerIconSize: CGFloat = 17
    static let headerIconFrame: CGFloat = 32
}
