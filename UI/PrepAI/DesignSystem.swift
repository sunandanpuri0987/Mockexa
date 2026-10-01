import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self { case .light: "sun.max.fill"; case .dark: "moon.stars.fill" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .light: .light; case .dark: .dark }
    }
}

struct ThemeSelectorControl: View {
    @Binding var selectedRaw: String
    @Namespace private var themeAnimation

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppAppearance.allCases) { option in
                let isSelected = selectedRaw == option.rawValue
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedRaw = option.rawValue
                    }
                    Haptics.selection()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: option.icon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(isSelected ? .white : PrepTheme.darkNavy)

                        Text(option.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(isSelected ? .white : PrepTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PrepTheme.gradient)
                                .matchedGeometryEffect(id: "ActiveThemeTab", in: themeAnimation)
                                .shadow(color: PrepTheme.primary.opacity(0.35), radius: 8, y: 3)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(PrepTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(PrepTheme.border, lineWidth: 1)
                                )
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select \(option.title) appearance")
            }
        }
    }
}

struct QuickThemeToggle: View {
    @AppStorage("PREPAI_APPEARANCE") private var appearanceRaw = AppAppearance.light.rawValue

    private var current: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .light
    }

    var body: some View {
        Menu {
            ForEach(AppAppearance.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appearanceRaw = option.rawValue
                    }
                    Haptics.selection()
                } label: {
                    Label(
                        option.title,
                        systemImage: appearanceRaw == option.rawValue ? "checkmark" : option.icon
                    )
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current.icon)
                    .font(.system(size: 14, weight: .bold))
                Text(current.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            }
            .foregroundStyle(PrepTheme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(PrepTheme.surface, in: Capsule())
            .overlay(Capsule().stroke(PrepTheme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
        }
        .accessibilityLabel("Change Theme: currently \(current.title)")
    }
}

enum PrepTheme {
    // Semantic system colors respond correctly even when the app-level color
    // scheme is changed at runtime through preferredColorScheme.
    static let primary = Color(red: 13/255, green: 148/255, blue: 136/255)
    static let secondary = Color(red: 45/255, green: 212/255, blue: 191/255)
    static let darkNavy = Color.primary
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.55)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let success = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)     // Amber Warning
    static let destructive = Color(red: 239/255, green: 68/255, blue: 68/255)   // Red Destructive
    static let gradient = LinearGradient(
        colors: [primary, Color(red: 13/255, green: 110/255, blue: 103/255)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            PrepTheme.background.ignoresSafeArea()
            
            // Soft Mint Atmospheric Studio Glow
            RadialGradient(
                colors: [
                    PrepTheme.secondary.opacity(0.06),
                    PrepTheme.primary.opacity(0.02),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.35),
                startRadius: 20,
                endRadius: 360
            )
            .ignoresSafeArea()
        }
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        content
            .padding(20)
            .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(PrepTheme.border, lineWidth: 1))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.055), radius: 12, y: 5)
    }
}

struct PrimaryButtonLabel: View {
    let title: String
    var icon: String? = nil
    var isPressed: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .offset(x: isPressed ? 5 : 0)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(PrepTheme.gradient, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: PrepTheme.primary.opacity(isPressed ? 0.35 : 0.22), radius: isPressed ? 6 : 12, y: isPressed ? 2 : 5)
    }
}

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: { action() }) {
            PrimaryButtonLabel(title: title, icon: icon, isPressed: isPressed)
        }
        .buttonStyle(PrimaryPressableButtonStyle(isPressed: $isPressed))
    }
}


struct PrimaryPressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .onChange(of: configuration.isPressed) { _, pressed in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    isPressed = pressed
                }
                if pressed { Haptics.selection() }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: { action() }) {
            SecondaryButtonLabel(title: title, icon: icon, isPressed: isPressed)
        }
        .buttonStyle(PrimaryPressableButtonStyle(isPressed: $isPressed))
    }
}

/// A non-interactive secondary-button appearance for use as a NavigationLink label.
/// Keeping the visual label separate avoids nesting a Button inside NavigationLink.
struct SecondaryButtonLabel: View {
    let title: String
    var icon: String? = nil
    var isPressed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .offset(x: isPressed ? 4 : 0)
            }
        }
        .foregroundStyle(PrepTheme.darkNavy)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(PrepTheme.surface, in: RoundedRectangle(cornerRadius: 27))
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(PrepTheme.border, lineWidth: 1))
        .shadow(color: Color.black.opacity(isPressed ? 0.06 : 0.03), radius: isPressed ? 3 : 6, y: isPressed ? 1 : 2)
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Touchscreen Interactive 3D Card Container
private struct TouchCardPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isTouchCardPressed: Bool {
        get { self[TouchCardPressedKey.self] }
        set { self[TouchCardPressedKey.self] = newValue }
    }
}

struct TouchCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.isTouchCardPressed, configuration.isPressed)
    }
}

struct InteractiveTouchCard<Content: View>: View {
    var maxTilt: Double = 5.0
    var action: () -> Void = {}
    @ViewBuilder var content: (_ isPressed: Bool) -> Content
    
    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            InteractiveTouchCardBody(maxTilt: maxTilt, content: content)
        }
        .buttonStyle(TouchCardButtonStyle())
    }
}

struct InteractiveTouchCardBody<Content: View>: View {
    let maxTilt: Double
    @ViewBuilder let content: (_ isPressed: Bool) -> Content
    
    @Environment(\.isTouchCardPressed) private var isPressed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        content(isPressed)
            .scaleEffect(reduceMotion ? 1.0 : (isPressed ? 0.975 : 1.0))
            .rotation3DEffect(.degrees(reduceMotion || !isPressed ? 0 : -maxTilt * 0.4), axis: (x: 1, y: 0, z: 0))
            .shadow(
                color: Color.black.opacity(isPressed ? 0.08 : 0.035),
                radius: isPressed ? 4 : 12,
                x: 0,
                y: isPressed ? 2 : 5
            )
            .animation(.spring(response: 0.26, dampingFraction: 0.72), value: isPressed)
    }
}




// MARK: - Ambient Moving Hero Light Glow
struct HeroAmbientGlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let offsetX = reduceMotion ? 0 : sin(phase * 0.5) * 16.0
            let offsetY = reduceMotion ? 0 : cos(phase * 0.4) * 10.0
            
            ZStack {
                Circle()
                    .fill(PrepTheme.secondary.opacity(0.14))
                    .frame(width: 140, height: 140)
                    .blur(radius: 28)
                    .offset(x: offsetX - 30, y: offsetY - 10)
                
                Circle()
                    .fill(PrepTheme.primary.opacity(0.12))
                    .frame(width: 160, height: 160)
                    .blur(radius: 32)
                    .offset(x: -offsetX + 30, y: -offsetY + 10)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Staggered Entrance Animation
struct StaggeredEntranceModifier: ViewModifier {
    let delay: Double
    let offset: CGFloat
    @State private var isAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    func body(content: Content) -> some View {
        content
            .opacity(isAppeared ? 1 : 0)
            .scaleEffect(reduceMotion ? 1.0 : (isAppeared ? 1.0 : 0.98))
            .offset(y: reduceMotion ? 0 : (isAppeared ? 0 : offset))
            .onAppear {
                if reduceMotion {
                    isAppeared = true
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82).delay(delay)) {
                        isAppeared = true
                    }
                }
            }
    }
}

// MARK: - Subtle Emerald Ambient Glow
struct SubtleEmeraldGlowModifier: ViewModifier {
    var active: Bool = true
    func body(content: Content) -> some View {
        content
            .shadow(color: active ? PrepTheme.primary.opacity(0.14) : Color.clear, radius: 14, x: 0, y: 6)
    }
}

struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(PrepTheme.darkNavy)
            Spacer()
            if let action {
                Button(action) {
                    Haptics.selection()
                    onAction?()
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PrepTheme.primary)
            }
        }
    }
}


struct AIAvatar: View {
    let initials: String
    var color: Color = PrepTheme.primary
    var active = false
    var body: some View {
        ZStack {
            if active {
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 4)
                    .scaleEffect(1.15)
            }
            Circle()
                .fill(LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
        .shadow(color: active ? color.opacity(0.3) : Color.black.opacity(0.05), radius: 8)
        .accessibilityLabel("AI participant \(initials)\(active ? ", speaking" : "")")
    }
}

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 150
    @State private var progress = 0.0
    @State private var displayScore = 0
    @State private var hasAnimated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(PrepTheme.border, lineWidth: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(PrepTheme.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(displayScore)")
                    .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                    .foregroundStyle(PrepTheme.darkNavy)
                    .contentTransition(.numericText())
                Text("out of 100")
                    .font(.system(size: size * 0.09, weight: .medium))
                    .foregroundStyle(PrepTheme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !hasAnimated else { return }
            hasAnimated = true
            if reduceMotion {
                progress = Double(score) / 100.0
                displayScore = score
            } else {
                withAnimation(.easeOut(duration: 1.1)) {
                    progress = Double(score) / 100.0
                    displayScore = score
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(score) out of 100")
    }
}

struct WaveformView: View {
    var active: Bool
    var color: Color = PrepTheme.secondary
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !active)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: active ? 9 + abs(sin(phase * 4 + Double(i))) * 23 : 8)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: phase)
        }
        .frame(height: 38)
        .accessibilityHidden(true)
    }
}

extension View {
    func staggeredEntrance(delay: Double, offset: CGFloat = 18) -> some View {
        modifier(StaggeredEntranceModifier(delay: delay, offset: offset))
    }
    
    func subtleEmeraldGlow(active: Bool = true) -> some View {
        modifier(SubtleEmeraldGlowModifier(active: active))
    }
    
    func screenTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(PrepTheme.darkNavy)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(PrepTheme.textSecondary)
            }
            self
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
