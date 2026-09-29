import SwiftUI
import UserNotifications

struct DelayControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                VStack(spacing: 10) {
                    Text(model.delay == 0 ? "Live" : AppModel.format(model.delay))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(model.delay == 0 ? Theme.live : Theme.held)
                    Text(model.delay == 0 ? "Alerts arrive as it happens" : "Every alert and lock-screen update waits this long")
                        .font(.footnote).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        nudge(-5)
                        Slider(value: Binding(get: { Double(model.delay) },
                                              set: { model.delay = Int($0 / 5) * 5; model.presetName = "Custom" }),
                               in: 0...600)
                            .tint(Theme.held)
                        nudge(5)
                    }
                }
                .padding(.vertical, 6)
                .listRowBackground(Color.clear)
            }
            Section("I'm watching on") {
                ForEach(DelayPreset.all) { p in
                    Button {
                        withAnimation(.snappy) { model.delay = p.seconds; model.presetName = p.name }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).foregroundStyle(.primary)
                                if !p.note.isEmpty { Text(p.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Text(AppModel.format(p.seconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            if model.presetName == p.name {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            Section {
                Text("Streams drift. If an alert still beats the play, nudge it up 5 seconds at a time until it lands just after.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func nudge(_ by: Int) -> some View {
        Button {
            withAnimation { model.delay = max(0, min(900, model.delay + by)); model.presetName = "Custom" }
        } label: {
            Image(systemName: by < 0 ? "minus" : "plus").frame(width: 22, height: 22)
        }
        .buttonStyle(.glass)
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var permission = "Checking…"

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section("Delay") {
                    NavigationLink {
                        DelayControls().navigationTitle("Delay")
                    } label: {
                        HStack {
                            Label("How far behind", systemImage: "timer")
                            Spacer()
                            Text(model.delay == 0 ? "Live" : "\(AppModel.format(model.delay)) · \(model.presetName)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Hide live scores I can't hold", isOn: $model.prefs.maskWhenUnsure)
                }
                Section {
                    Toggle("Game starts", isOn: $model.prefs.start)
                    Toggle("Scores", isOn: $model.prefs.score)
                    Toggle("Every basket", isOn: $model.prefs.everyBasket)
                        .disabled(!model.prefs.score)
                    Toggle("End of each period", isOn: $model.prefs.period)
                    Toggle("Finals", isOn: $model.prefs.final)
                    Toggle("Delays and restarts", isOn: $model.prefs.delay)
                } header: { Text("Alerts") } footer: {
                    Text("Basketball sends period ends and the final unless Every basket is on.")
                }
                Section {
                    Toggle("Start Live Activities for my games", isOn: $model.prefs.liveActivities)
                } footer: {
                    Text("When a followed game starts, it appears on your lock screen and in the Dynamic Island, held by the same delay.")
                }
                Section("Notifications") {
                    HStack { Text("Permission"); Spacer(); Text(permission).foregroundStyle(.secondary) }
                    if permission != "Allowed" {
                        Button("Allow notifications") {
                            Task { _ = await Push.shared?.requestPermission(); await check() }
                        }
                    }
                    Text(model.relayStatus).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("Scores from ESPN. Held alerts come from a relay on BasilNet that listens to ESPN's live feed and sends each push late by your delay.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { await check() }
        }
    }

    private func check() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        switch s.authorizationStatus {
        case .authorized, .provisional, .ephemeral: permission = "Allowed"
        case .denied: permission = "Off in iOS Settings"
        default: permission = "Not asked yet"
        }
    }
}
