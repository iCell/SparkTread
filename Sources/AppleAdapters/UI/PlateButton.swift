import SwiftUI

/// The menus' button language (owner 2026-10-06: the native capsules looked
/// like stock controls, and the complaint was about arrangement as much as
/// looks). One language for every screen, taken from the wordmark: the two
/// materials the game is made of — the fire yellow for THE action on a
/// screen, the arena's steel for everything else — on a hard extruded block
/// with a dark rim and a top sheen, and a press that sinks the face onto its
/// base. Squared corners, not capsules: these are plates, like the walls.
///
/// Arrangement rule, applied by every screen that uses these: one primary
/// plate, large, alone on its row; the secondary plates in one row under it,
/// regular size; small plates only inside panels. Labels are native text —
/// Chinese is never baked into art.
enum PlateRole { case primary, secondary }

enum PlateSize {
    case large, regular, small

    var height: CGFloat { switch self { case .large: 54; case .regular: 42; case .small: 30 } }
    var minWidth: CGFloat { switch self { case .large: 260; case .regular: 150; case .small: 0 } }
    var horizontalPadding: CGFloat { switch self { case .large: 28; case .regular: 20; case .small: 12 } }
    /// The extrusion: how far the face stands off its base, and how far a
    /// press sinks it.
    var depth: CGFloat { switch self { case .large: 5; case .regular: 4; case .small: 3 } }
    var radius: CGFloat { switch self { case .large: 5; case .regular: 4; case .small: 3 } }
    var font: Font {
        switch self {
        case .large: .system(size: 21, weight: .heavy, design: .rounded)
        case .regular: .system(size: 17, weight: .bold, design: .rounded)
        case .small: .system(size: 13, weight: .bold, design: .rounded)
        }
    }
    var iconSize: CGFloat { switch self { case .large: 17; case .regular: 14; case .small: 11 } }
}

/// The two materials, as the wordmark paints them.
struct PlateFace {
    let top: Color, bottom: Color, rim: Color, base: Color, ink: Color

    static let fire = PlateFace(top: Color(red: 1.00, green: 0.88, blue: 0.30),
                                bottom: Color(red: 0.98, green: 0.68, blue: 0.10),
                                rim: Color(red: 0.30, green: 0.15, blue: 0.02),
                                base: Color(red: 0.55, green: 0.30, blue: 0.04),
                                ink: Color(red: 0.16, green: 0.09, blue: 0.02))
    static let steel = PlateFace(top: Color(red: 0.42, green: 0.48, blue: 0.53),
                                 bottom: Color(red: 0.26, green: 0.31, blue: 0.35),
                                 rim: Color(red: 0.07, green: 0.09, blue: 0.11),
                                 base: Color(red: 0.12, green: 0.15, blue: 0.18),
                                 ink: .white.opacity(0.94))

    static func of(_ role: PlateRole) -> PlateFace { role == .primary ? .fire : .steel }
}

struct PlateButtonStyle: ButtonStyle {
    var role: PlateRole = .secondary
    var size: PlateSize = .regular
    /// A toggle drawn as the primary material while it is the chosen one
    /// (difficulty, training-panel options).
    var selected = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let face = PlateFace.of(selected ? .primary : role)
        let pressed = configuration.isPressed
        configuration.label
            .font(size.font)
            .foregroundStyle(face.ink)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: size.minWidth, minHeight: size.height)
            .background {
                ZStack {
                    // The base stays put; the face sinks onto it when pressed.
                    RoundedRectangle(cornerRadius: size.radius)
                        .fill(face.base)
                        .offset(y: size.depth)
                    RoundedRectangle(cornerRadius: size.radius)
                        .fill(LinearGradient(colors: [face.top, face.bottom], startPoint: .top, endPoint: .bottom))
                        .brightness(pressed ? -0.07 : 0)
                        .overlay {
                            // Sheen along the top edge, inside the rim.
                            RoundedRectangle(cornerRadius: max(0, size.radius - 1.5))
                                .strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                                             startPoint: .top, endPoint: .center), lineWidth: 1)
                                .padding(1.5)
                        }
                        .overlay(RoundedRectangle(cornerRadius: size.radius).strokeBorder(face.rim, lineWidth: 1.5))
                        .offset(y: pressed ? size.depth : 0)
                }
            }
            .offset(y: pressed ? size.depth : 0)
            .padding(.bottom, size.depth)   // the base is part of the plate's footprint
            .saturation(isEnabled ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.07), value: pressed)
    }
}

/// A plate with a label and an optional symbol in front of it.
struct PlateButton: View {
    let title: String
    var icon: String?
    var role: PlateRole = .secondary
    var size: PlateSize = .regular
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: size == .large ? 10 : 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .heavy))
                }
                Text(title)
            }
        }
        .buttonStyle(PlateButtonStyle(role: role, size: size))
    }
}

/// A row of small plates where exactly one is chosen (difficulty).
struct PlateSegments<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    let selection: ID
    let onSelect: (ID) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.id) { option in
                Button(option.label) { onSelect(option.id) }
                    .buttonStyle(PlateButtonStyle(role: .secondary, size: .small, selected: option.id == selection))
            }
        }
    }
}

/// The panel the overlays sit on — pause, results — in the same steel: a
/// dark plate with a steel rim and its own base, so a panel and the buttons
/// on it are one object rather than a yellow-framed box with white pills.
struct PlatePanel: ViewModifier {
    var radius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(PlateFace.steel.base)
                        .offset(y: 6)
                    RoundedRectangle(cornerRadius: radius)
                        .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.19),
                                                      Color(red: 0.08, green: 0.10, blue: 0.12)],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: radius)
                            .strokeBorder(PlateFace.steel.top, lineWidth: 2))
                        .overlay(RoundedRectangle(cornerRadius: radius - 2)
                            .strokeBorder(PlateFace.steel.rim, lineWidth: 1.5)
                            .padding(2))
                }
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 6)
            }
            .padding(.bottom, 6)
    }
}

extension View {
    func platePanel(radius: CGFloat = 10) -> some View { modifier(PlatePanel(radius: radius)) }
}
