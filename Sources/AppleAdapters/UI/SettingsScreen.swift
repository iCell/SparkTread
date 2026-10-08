import SwiftUI

/// Settings (owner 2026-10-08): language, sound, haptics, the controls'
/// handedness, and the accessibility options — in the plate language, on
/// the menu backdrop, with the same borderless back button as the select
/// screen. Every row is a labelled group of small plates (the selected one
/// in fire), so nothing here is a native switch or picker.
struct SettingsScreen: View {
    let onBack: () -> Void
    @Environment(SettingsStore.self) private var settings
    @Environment(\.strings) private var strings

    var body: some View {
        VStack(spacing: 14) {
            Text(strings("settings.title"))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.yellow)
                .padding(.top, 2)
            ScrollView(.vertical, showsIndicators: false) {
                SettingsList()
                    .padding(.horizontal, 60)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 760)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button(action: onBack) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(Color.yellow)
                    Text(strings("common.back"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .shadow(color: .black.opacity(0.85), radius: 4, x: 0, y: 1)
                .padding(.vertical, 10)
                .padding(.trailing, 16)
                .contentShape(Rectangle())
            }
            .padding(.leading, 22)
            .padding(.top, 18)
        }
        .background(MenuBackdrop())
    }

}

/// The settings themselves, outside the scroll view so they can be
/// rendered on their own (offscreen checks do not render scroll content).
struct SettingsList: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.strings) private var strings

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 18) {
            section(strings("settings.language")) {
                // The six languages by their own names, never translated, so
                // the wrong language can still be undone. No "system" entry
                // (owner 2026-10-08): the phone's language is simply the one
                // selected until the player picks another.
                PlateSegments(options: AppLanguage.allCases.map { ($0.rawValue, $0.nativeName) },
                              selection: settings.effectiveLanguage.rawValue) { id in
                    settings.language = AppLanguage(rawValue: id)
                }
            }
            section(strings("settings.sound")) {
                toggle(strings("settings.sound.enabled"), $settings.soundEnabled)
                row(strings("settings.sound.volume")) {
                    PlateSegments(options: [0.25, 0.5, 0.75, 1.0].map { (String($0), "\(Int($0 * 100))%") },
                                  selection: String(Self.volumeStep(settings.soundVolume))) { id in
                        settings.soundVolume = Double(id) ?? 1
                    }
                }
                .disabled(!settings.soundEnabled)
                .opacity(settings.soundEnabled ? 1 : 0.5)
            }
            section(strings("settings.haptics")) {
                toggle(strings("settings.haptics"), $settings.hapticsEnabled)
            }
            section(strings("settings.controls")) {
                toggle(strings("settings.controls.mirror"), $settings.mirrorControls)
            }
            section(strings("settings.accessibility")) {
                toggle(strings("settings.reduceMotion"), $settings.reduceMotion)
                toggle(strings("settings.highContrast"), $settings.highContrastHUD)
                toggle(strings("settings.largeHUD"), $settings.largeHUD)
            }
        }
    }

    /// The volume plates are quarter steps; a stored value in between
    /// (from a future slider) snaps up to the nearest plate.
    private static func volumeStep(_ volume: Double) -> Double {
        [0.25, 0.5, 0.75, 1.0].first { volume <= $0 + 0.001 } ?? 1.0
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.yellow.opacity(0.9))
                .textCase(.uppercase)
            content()
        }
    }

    @ViewBuilder private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 14) {
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(minWidth: 150, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func toggle(_ label: String, _ value: Binding<Bool>) -> some View {
        row(label) {
            PlateSegments(options: [(true, strings("common.on")), (false, strings("common.off"))],
                          selection: value.wrappedValue) { value.wrappedValue = $0 }
        }
    }
}
