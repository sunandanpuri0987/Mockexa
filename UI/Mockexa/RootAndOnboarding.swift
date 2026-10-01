import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel
    var body: some View {
        ZStack {
            AppBackground()
            switch app.route {
            case .splash:
                SplashView()
                    .foregroundStyle(.white)
            case .welcome:
                WelcomeView()
                    .foregroundStyle(.white)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.97))
                    ))
            case .auth:
                AuthenticationView()
                    .foregroundStyle(.white)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 1.02)),
                        removal: .opacity
                    ))
            case .onboarding:
                OnboardingView()
                    .foregroundStyle(.white)
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.route)
    }
}

struct SplashView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    @State private var entranceDone = false
    @State private var pulseGlow = false
    @State private var isZooming = false
    @State private var backgroundOpacity: Double = 1.0
    
    private let darkBackground = Color(red: 8/255, green: 12/255, blue: 22/255)
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let mintGlowColor = Color(red: 16/255, green: 185/255, blue: 129/255)

    private func routeAfterSplash() {
        Task { @MainActor in
            while auth.isRestoringSession {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if auth.isAuthenticated {
                if auth.isOnboardingCompleted(for: auth.currentUserId) {
                    app.route = .main
                } else {
                    app.onboardingStep = 0
                    app.route = .onboarding
                }
            } else {
                app.route = .welcome
            }
        }
    }

    var body: some View {
        ZStack {
            // Clean dark premium background with subtle emerald radial glow
            ZStack {
                darkBackground
                
                RadialGradient(
                    colors: [
                        mintGlowColor.opacity(reduceMotion ? 0.12 : (isZooming ? 0.35 : (pulseGlow ? 0.20 : 0.12))),
                        emeraldColor.opacity(0.04),
                        .clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 340
                )
            }
            .ignoresSafeArea()
            .opacity(backgroundOpacity)
            
            // Centered Logo & Branding using exact MockexaLogoIcon component
            VStack(spacing: 18) {
                ZStack {
                    // Soft ambient emerald glow behind logo
                    Circle()
                        .fill(mintGlowColor.opacity(reduceMotion ? 0.15 : (isZooming ? 0.35 : (pulseGlow ? 0.25 : 0.16))))
                        .frame(width: 100, height: 100)
                        .blur(radius: reduceMotion ? 16 : 28)
                        .scaleEffect(reduceMotion ? 1.0 : (isZooming ? 4.5 : (pulseGlow ? 1.08 : 0.96)))
                    
                    // Canonical folded geometric M logo
                    MockexaLogoIcon()
                        .scaleEffect(reduceMotion ? 1.6 : (isZooming ? 24.0 : (entranceDone ? 1.6 : 1.2)))
                        .opacity(isZooming ? 0.0 : (entranceDone ? 1.0 : 0.0))
                        .offset(y: reduceMotion ? 0 : (isZooming ? 0 : (entranceDone ? 0 : 16)))
                }
                
                // Brand wordmark matching Get Started page style
                Text("MOCKEXA")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(3.5)
                    .foregroundStyle(.white)
                    .opacity(isZooming ? 0.0 : (entranceDone ? 1.0 : 0.0))
                    .offset(y: reduceMotion ? 0 : (isZooming ? 10 : (entranceDone ? 0 : 12)))
                    .scaleEffect(isZooming ? 1.3 : 1.0)
            }
        }
        .task {
            if reduceMotion {
                entranceDone = true
                try? await Task.sleep(for: .milliseconds(1300))
                withAnimation(.easeInOut(duration: 0.35)) {
                    backgroundOpacity = 0.0
                }
                try? await Task.sleep(for: .milliseconds(350))
                routeAfterSplash()
            } else {
                // 1. Entrance animation (0.0s - 0.7s)
                withAnimation(.spring(response: 0.65, dampingFraction: 0.78)) {
                    entranceDone = true
                }
                
                // Ambient glow subtle pulse
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    pulseGlow = true
                }
                
                // 2. Hold phase (0.7s - 1.9s: 1.2s delay)
                try? await Task.sleep(for: .milliseconds(1200))
                
                // 3. Logo zoom & smooth screen reveal (1.9s - 2.5s: 0.6s duration)
                withAnimation(.easeInOut(duration: 0.6)) {
                    isZooming = true
                    backgroundOpacity = 0.0
                }
                
                try? await Task.sleep(for: .milliseconds(600))
                routeAfterSplash()
            }
        }
    }
}

struct LogoMark: View {
    var body: some View { ZStack { RoundedRectangle(cornerRadius: 24).fill(MockexaTheme.gradient).frame(width: 82, height: 82); Image(systemName: "bubble.left.and.sparkles.fill").font(.system(size: 35)).foregroundStyle(.white) }.shadow(color: MockexaTheme.primary.opacity(0.5), radius: 30) }
}

struct MockexaLogoIcon: View {
    private let navyFace = LinearGradient(
        colors: [Color(red: 15/255, green: 23/255, blue: 42/255), Color(red: 30/255, green: 41/255, blue: 59/255)],
        startPoint: .top, endPoint: .bottom
    )
    private let emeraldStructure = LinearGradient(
        colors: [Color(red: 15/255, green: 90/255, blue: 71/255), Color(red: 6/255, green: 78/255, blue: 59/255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let emeraldDarkStructure = LinearGradient(
        colors: [Color(red: 10/255, green: 75/255, blue: 58/255), Color(red: 4/255, green: 55/255, blue: 40/255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let mintGlassFold = LinearGradient(
        colors: [Color(red: 52/255, green: 211/255, blue: 153/255).opacity(0.85), Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.35)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let strokeGradient = LinearGradient(
        colors: [Color(red: 52/255, green: 211/255, blue: 153/255), Color(red: 15/255, green: 90/255, blue: 71/255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack {
            // 1. Dark Navy Structural Outer Pillars
            Path { path in
                path.move(to: CGPoint(x: 4, y: 10))
                path.addLine(to: CGPoint(x: 11, y: 10))
                path.addLine(to: CGPoint(x: 11, y: 36))
                path.addLine(to: CGPoint(x: 4, y: 36))
                path.closeSubpath()
                
                path.move(to: CGPoint(x: 29, y: 10))
                path.addLine(to: CGPoint(x: 36, y: 10))
                path.addLine(to: CGPoint(x: 36, y: 36))
                path.addLine(to: CGPoint(x: 29, y: 36))
                path.closeSubpath()
            }
            .fill(navyFace)

            // 2. Emerald Green Structural Diagonal Folds
            Path { path in
                path.move(to: CGPoint(x: 4, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 26))
                path.addLine(to: CGPoint(x: 20, y: 33))
                path.addLine(to: CGPoint(x: 11, y: 19))
                path.closeSubpath()
            }
            .fill(emeraldStructure)

            Path { path in
                path.move(to: CGPoint(x: 36, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 26))
                path.addLine(to: CGPoint(x: 20, y: 33))
                path.addLine(to: CGPoint(x: 29, y: 19))
                path.closeSubpath()
            }
            .fill(emeraldDarkStructure)

            // 3. Mint Translucent Glass Highlight Facet
            Path { path in
                path.move(to: CGPoint(x: 4, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 26))
                path.addLine(to: CGPoint(x: 11, y: 17))
                path.closeSubpath()
            }
            .fill(mintGlassFold)

            // 4. Crisp Geometry Outline Stroke
            Path { path in
                path.move(to: CGPoint(x: 4, y: 36))
                path.addLine(to: CGPoint(x: 4, y: 10))
                path.addLine(to: CGPoint(x: 20, y: 26))
                path.addLine(to: CGPoint(x: 36, y: 10))
                path.addLine(to: CGPoint(x: 36, y: 36))
            }
            .stroke(
                strokeGradient,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(width: 40, height: 40)
    }
}

struct MockexaHeroGraphic: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var floatOffset: CGFloat = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotationAngle: Double = 0
    @State private var dragTranslation: CGSize = .zero
    
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let mintGlowColor = Color(red: 16/255, green: 185/255, blue: 129/255)
    
    private var logoParallaxOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let maxOffset: CGFloat = 4.0
        let dx = min(max(dragTranslation.width * 0.08, -maxOffset), maxOffset)
        let dy = min(max(dragTranslation.height * 0.08, -maxOffset), maxOffset)
        return CGSize(width: dx, height: dy)
    }

    private var orbitParallaxOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let maxOffset: CGFloat = 7.0
        let dx = min(max(dragTranslation.width * 0.14, -maxOffset), maxOffset)
        let dy = min(max(dragTranslation.height * 0.14, -maxOffset), maxOffset)
        return CGSize(width: dx, height: dy)
    }

    private var particleParallaxOffset: CGSize {
        guard !reduceMotion else { return .zero }
        let maxOffset: CGFloat = 10.0
        let dx = min(max(dragTranslation.width * 0.20, -maxOffset), maxOffset)
        let dy = min(max(dragTranslation.height * 0.20, -maxOffset), maxOffset)
        return CGSize(width: dx, height: dy)
    }
    
    var body: some View {
        ZStack {
            // Faint concentric orbits
            ZStack {
                Circle()
                    .stroke(emeraldColor.opacity(0.11), lineWidth: 1.5)
                    .frame(width: 220, height: 220)
                    .scaleEffect(reduceMotion ? 1.0 : pulseScale)
                    .rotationEffect(.degrees(reduceMotion ? 0 : rotationAngle))
                
                Circle()
                    .stroke(emeraldColor.opacity(0.07), lineWidth: 1)
                    .frame(width: 280, height: 280)
                    .rotationEffect(.degrees(reduceMotion ? 0 : -rotationAngle * 0.5))
            }
            .offset(x: orbitParallaxOffset.width, y: orbitParallaxOffset.height)
            
            // Soft mint radial glow background
            RadialGradient(
                colors: [
                    mintGlowColor.opacity(0.16),
                    emeraldColor.opacity(0.03),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 150
            )
            .frame(width: 300, height: 300)
            
            // Floating accent particles with depth parallax
            ZStack {
                Circle()
                    .fill(emeraldColor.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .offset(x: -95, y: -40 + (reduceMotion ? 0 : floatOffset * 0.4))
                
                Circle()
                    .fill(mintGlowColor.opacity(0.5))
                    .frame(width: 8, height: 8)
                    .offset(x: 85, y: -60 - (reduceMotion ? 0 : floatOffset * 0.3))
                
                Circle()
                    .fill(emeraldColor.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .offset(x: 105, y: 45 + (reduceMotion ? 0 : floatOffset * 0.5))
            }
            .offset(x: particleParallaxOffset.width, y: particleParallaxOffset.height)
            
            // Center 3D Glass Badge with Refined Layered Shadow & Visibly Noticeable Soft Emerald Glow
            ZStack {
                // Soft ambient emerald aura extending behind card
                Circle()
                    .fill(mintGlowColor.opacity(reduceMotion ? 0.22 : (pulseScale > 1.01 ? 0.32 : 0.22)))
                    .frame(width: 135, height: 135)
                    .blur(radius: 28)
                
                // Rotated White Glass Card
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white)
                    .shadow(color: emeraldColor.opacity(0.16), radius: 24, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(45))
                
                ZStack {
                    // Soft emerald-green ambient glow centered directly behind the logo
                    Circle()
                        .fill(mintGlowColor.opacity(reduceMotion ? 0.30 : (pulseScale > 1.01 ? 0.42 : 0.30)))
                        .frame(width: 90, height: 90)
                        .blur(radius: 24)
                        .scaleEffect(reduceMotion ? 1.0 : (pulseScale > 1.01 ? 1.12 : 0.98))
                    
                    MockexaLogoIcon()
                        .scaleEffect(1.25)
                }
            }
            .offset(x: logoParallaxOffset.width, y: (reduceMotion ? 0 : floatOffset) + logoParallaxOffset.height)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !reduceMotion else { return }
                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.86)) {
                        dragTranslation = value.translation
                    }
                }
                .onEnded { _ in
                    guard !reduceMotion else { return }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        dragTranslation = .zero
                    }
                }
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                floatOffset = -5
                pulseScale = 1.02
            }
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    @State private var headerAppear = false
    @State private var headlineAppear = false
    @State private var subtitleAppear = false
    @State private var gdAppear = false
    @State private var techAppear = false
    @State private var hrAppear = false
    @State private var heroAppear = false
    @State private var ctaAppear = false
    @State private var footerAppear = false
    
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let mintGlowColor = Color(red: 16/255, green: 185/255, blue: 129/255)
    
    var body: some View {
        ZStack {
            // 1. Warm off-white clean background matching reference image
            Color(red: 248/255, green: 250/255, blue: 252/255)
                .ignoresSafeArea()
            
            // 2. Center Soft Mint/Emerald Atmospheric Glow behind Hero
            RadialGradient(
                colors: [
                    mintGlowColor.opacity(0.08),
                    emeraldColor.opacity(0.03),
                    .clear
                ],
                center: UnitPoint(x: 0.5, y: 0.52),
                startRadius: 20,
                endRadius: 320
            )
            .ignoresSafeArea()
            
            // 3. Left Side Soft Green Ambient Studio Light
            RadialGradient(
                colors: [
                    mintGlowColor.opacity(0.045),
                    .clear
                ],
                center: UnitPoint(x: 0.0, y: 0.55),
                startRadius: 30,
                endRadius: 340
            )
            .ignoresSafeArea()
            
            // 4. Right Side Soft Green Ambient Studio Light
            RadialGradient(
                colors: [
                    mintGlowColor.opacity(0.035),
                    .clear
                ],
                center: UnitPoint(x: 1.0, y: 0.45),
                startRadius: 30,
                endRadius: 340
            )
            .ignoresSafeArea()
            
            GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                // Top Brand Header
                HStack(spacing: 8) {
                    MockexaLogoIcon()
                        .scaleEffect(headerAppear || reduceMotion ? 0.65 : 0.62)
                        .frame(width: 26, height: 26)
                    
                    Text("MOCKEXA")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color(red: 15/255, green: 23/255, blue: 42/255))
                    
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .opacity(headerAppear || reduceMotion ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (headerAppear ? 0 : -6))
                
                Spacer(minLength: 12)
                
                // Headline & Subtitle Area
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your next")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 15/255, green: 23/255, blue: 42/255))
                        
                        Text("interview")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 15/255, green: 23/255, blue: 42/255))
                        
                        Text("starts here.")
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(emeraldColor)
                    }
                    .opacity(headlineAppear || reduceMotion ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (headlineAppear ? 0 : 10))
                    
                    Text("AI-powered mock interviews\nto help you practice, learn\nand get interview-ready.")
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundStyle(Color(red: 71/255, green: 85/255, blue: 105/255))
                        .lineSpacing(5)
                        .opacity(subtitleAppear || reduceMotion ? 1 : 0)
                        .offset(y: reduceMotion ? 0 : (subtitleAppear ? 0 : 8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                
                Spacer(minLength: 12)
                
                // Plain Centered Interview Rounds Row
                HStack(spacing: 8) {
                    Text("GD")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 100/255, green: 116/255, blue: 139/255))
                        .opacity(gdAppear || reduceMotion ? 1 : 0)
                        .offset(y: reduceMotion ? 0 : (gdAppear ? 0 : 6))
                    
                    Text("•")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 148/255, green: 163/255, blue: 184/255))
                        .opacity(gdAppear || reduceMotion ? 1 : 0)
                    
                    Text("Technical")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 100/255, green: 116/255, blue: 139/255))
                        .opacity(techAppear || reduceMotion ? 1 : 0)
                        .offset(y: reduceMotion ? 0 : (techAppear ? 0 : 6))
                    
                    Text("•")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 148/255, green: 163/255, blue: 184/255))
                        .opacity(techAppear || reduceMotion ? 1 : 0)
                    
                    Text("HR")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 100/255, green: 116/255, blue: 139/255))
                        .opacity(hrAppear || reduceMotion ? 1 : 0)
                        .offset(y: reduceMotion ? 0 : (hrAppear ? 0 : 6))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Group Discussion, Technical, and HR mock interview rounds")
                
                Spacer(minLength: 14)
                
                // Hero Graphic Area
                MockexaHeroGraphic()
                    .frame(height: 260)
                    .opacity(heroAppear || reduceMotion ? 1 : 0)
                    .scaleEffect(reduceMotion ? 1.0 : (heroAppear ? 1.0 : 0.95))
                    .offset(y: reduceMotion ? 0 : (heroAppear ? 0 : 10))
                
                Spacer(minLength: 20)
                
                // Action Buttons Area
                VStack(spacing: 12) {
                    Button {
                        Haptics.selection()
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.45)) {
                            app.route = .auth
                        }
                    } label: {
                        HStack(spacing: 20) {
                            Text("Get Started")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .tracking(0.3)
                            
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 38, height: 38)
                                
                                GetStartedArrowView()
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 15/255, green: 90/255, blue: 71/255),
                                    Color(red: 10/255, green: 75/255, blue: 58/255)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 30)
                        )
                    }
                    .buttonStyle(GetStartedButtonStyle())
                    .opacity(ctaAppear || reduceMotion ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (ctaAppear ? 0 : 12))
                    
                    Text("Practice at your own pace and review feedback after every session")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color(red: 100/255, green: 116/255, blue: 139/255))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .opacity(footerAppear || reduceMotion ? 1 : 0)
                        .offset(y: reduceMotion ? 0 : (footerAppear ? 0 : 8))
                }
                .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .frame(minHeight: proxy.size.height)
                }
            }
        }
        .foregroundStyle(Color(red: 15/255, green: 23/255, blue: 42/255))
        .onAppear {
            if reduceMotion {
                headerAppear = true
                headlineAppear = true
                subtitleAppear = true
                gdAppear = true
                techAppear = true
                hrAppear = true
                heroAppear = true
                ctaAppear = true
                footerAppear = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) {
                    headerAppear = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.10)) {
                    headlineAppear = true
                }
                withAnimation(.easeOut(duration: 0.45).delay(0.18)) {
                    subtitleAppear = true
                }
                withAnimation(.easeOut(duration: 0.40).delay(0.24)) {
                    gdAppear = true
                }
                withAnimation(.easeOut(duration: 0.40).delay(0.32)) {
                    techAppear = true
                }
                withAnimation(.easeOut(duration: 0.40).delay(0.40)) {
                    hrAppear = true
                }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.46)) {
                    heroAppear = true
                }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.54)) {
                    ctaAppear = true
                }
                withAnimation(.easeOut(duration: 0.45).delay(0.62)) {
                    footerAppear = true
                }
            }
        }
    }
}

private struct IsBtnPressedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var isBtnPressed: Bool {
        get { self[IsBtnPressedKey.self] }
        set { self[IsBtnPressedKey.self] = newValue }
    }
}

struct GetStartedButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var idleBreathing = false
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.97 : 1.0))
            .shadow(
                color: emeraldColor.opacity(configuration.isPressed ? 0.42 : (idleBreathing ? 0.32 : 0.24)),
                radius: configuration.isPressed ? 20 : (idleBreathing ? 16 : 12),
                x: 0,
                y: configuration.isPressed ? 3 : 6
            )
            .environment(\.isBtnPressed, configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    idleBreathing = true
                }
            }
    }
}

struct GetStartedArrowView: View {
    @Environment(\.isBtnPressed) var isPressed
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 18, weight: .semibold))
            .offset(x: reduceMotion ? 0 : (isPressed ? 5 : 0))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
    }
}

struct GoogleGLogo: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 26.6, y: 14))
                p.addCurve(to: CGPoint(x: 26.32, y: 11.34), control1: CGPoint(x: 26.6, y: 13.09), control2: CGPoint(x: 26.53, y: 12.18))
                p.addLine(to: CGPoint(x: 14, y: 11.34))
                p.addLine(to: CGPoint(x: 14, y: 16.66))
                p.addLine(to: CGPoint(x: 21.07, y: 16.66))
                p.addCurve(to: CGPoint(x: 18.06, y: 22.26), control1: CGPoint(x: 20.44, y: 18.55), control2: CGPoint(x: 19.46, y: 20.79))
                p.addLine(to: CGPoint(x: 22.33, y: 25.55))
                p.addCurve(to: CGPoint(x: 26.6, y: 14), control1: CGPoint(x: 24.92, y: 23.17), control2: CGPoint(x: 26.6, y: 19.04))
            }
            .fill(Color(red: 66/255, green: 133/255, blue: 244/255))

            Path { p in
                p.move(to: CGPoint(x: 14, y: 26.81))
                p.addCurve(to: CGPoint(x: 22.33, y: 25.55), control1: CGPoint(x: 17.85, y: 26.81), control2: CGPoint(x: 20.44, y: 25.76))
                p.addLine(to: CGPoint(x: 18.06, y: 22.26))
                p.addCurve(to: CGPoint(x: 14, y: 23.45), control1: CGPoint(x: 16.87, y: 23.03), control2: CGPoint(x: 15.47, y: 23.45))
                p.addCurve(to: CGPoint(x: 5.04, y: 17.36), control1: CGPoint(x: 10.29, y: 23.45), control2: CGPoint(x: 7, y: 20.86))
                p.addLine(to: CGPoint(x: 0.77, y: 20.65))
                p.addCurve(to: CGPoint(x: 14, y: 26.81), control1: CGPoint(x: 3.36, y: 25.76), control2: CGPoint(x: 8.33, y: 26.81))
            }
            .fill(Color(red: 52/255, green: 168/255, blue: 83/255))

            Path { p in
                p.move(to: CGPoint(x: 5.04, y: 17.36))
                p.addCurve(to: CGPoint(x: 4.55, y: 14), control1: CGPoint(x: 4.69, y: 16.31), control2: CGPoint(x: 4.55, y: 15.19))
                p.addCurve(to: CGPoint(x: 5.04, y: 10.64), control1: CGPoint(x: 4.55, y: 12.81), control2: CGPoint(x: 4.69, y: 11.69))
                p.addLine(to: CGPoint(x: 0.77, y: 7.35))
                p.addCurve(to: CGPoint(x: 0, y: 14), control1: CGPoint(x: 0.28, y: 9.38), control2: CGPoint(x: 0, y: 11.62))
                p.addCurve(to: CGPoint(x: 0.77, y: 20.65), control1: CGPoint(x: 0, y: 16.38), control2: CGPoint(x: 0.28, y: 18.62))
                p.addLine(to: CGPoint(x: 5.04, y: 17.36))
            }
            .fill(Color(red: 251/255, green: 188/255, blue: 5/255))

            Path { p in
                p.move(to: CGPoint(x: 14, y: 4.55))
                p.addCurve(to: CGPoint(x: 20.58, y: 7.14), control1: CGPoint(x: 16.52, y: 4.55), control2: CGPoint(x: 18.83, y: 5.46))
                p.addLine(to: CGPoint(x: 24.57, y: 3.15))
                p.addCurve(to: CGPoint(x: 14, y: 1.19), control1: CGPoint(x: 21.77, y: 0.56), control2: CGPoint(x: 18.06, y: 1.19))
                p.addCurve(to: CGPoint(x: 0.77, y: 7.35), control1: CGPoint(x: 8.33, y: 1.19), control2: CGPoint(x: 3.36, y: 2.24))
                p.addLine(to: CGPoint(x: 5.04, y: 10.64))
                p.addCurve(to: CGPoint(x: 14, y: 4.55), control1: CGPoint(x: 7, y: 7.14), control2: CGPoint(x: 10.29, y: 4.55))
            }
            .fill(Color(red: 234/255, green: 67/255, blue: 53/255))
        }
        .frame(width: 28, height: 28)
    }
}

struct CompactProviderButton<IconContent: View>: View {
    let label: String
    let accessibilityLabel: String
    @ViewBuilder let icon: () -> IconContent
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            HStack(spacing: 8) {
                icon()
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 15/255, green: 23/255, blue: 42/255))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 226/255, green: 232/255, blue: 240/255), lineWidth: 1)
            )
            .shadow(color: Color(red: 15/255, green: 90/255, blue: 71/255).opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(TilePressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

struct TilePressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1.0 : (configuration.isPressed ? 0.96 : 1.0))
            .shadow(
                color: Color(red: 15/255, green: 90/255, blue: 71/255).opacity(configuration.isPressed ? 0.02 : 0.06),
                radius: configuration.isPressed ? 4 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 3
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct RequirementRow: View {
    let satisfied: Bool
    let text: String
    
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let subtextSlate = Color(red: 100/255, green: 116/255, blue: 139/255)
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(satisfied ? emeraldColor : subtextSlate.opacity(0.5))
            Text(text)
                .font(.system(size: 12, weight: satisfied ? .semibold : .regular))
                .foregroundStyle(satisfied ? emeraldColor : subtextSlate)
        }
    }
}

struct AuthenticationView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    
    enum Field: Hashable {
        case fullName
        case age
        case email
        case password
        case confirmPassword
    }
    
    @FocusState private var focusedField: Field?
    
    @State private var fullName = ""
    @State private var age = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var isSignUp = false
    @State private var showPhone = false
    @State private var showForgotAlert = false
    @State private var forgotSuccessMessage: String? = nil
    @State private var appearAnimation = false
    
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let darkNavy = Color(red: 15/255, green: 23/255, blue: 42/255)
    private let subtextSlate = Color(red: 100/255, green: 116/255, blue: 139/255)
    private let offWhiteBackground = Color(red: 248/255, green: 250/255, blue: 252/255)
    private let inputBg = Color(red: 241/255, green: 245/255, blue: 249/255)

    // MARK: - Password Requirements & Rules
    private var ruleLength: Bool { password.count >= 8 && password.count <= 128 }
    private var ruleUppercase: Bool { password.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var ruleLowercase: Bool { password.range(of: "[a-z]", options: .regularExpression) != nil }
    private var ruleNumber: Bool { password.range(of: "[0-9]", options: .regularExpression) != nil }
    private var ruleSpecial: Bool { password.range(of: "[!@#$%^&*()_\\-+=\\[\\]{}:;?.\\,/~]", options: .regularExpression) != nil }
    
    private var passwordSatisfiesAllRules: Bool {
        ruleLength && ruleUppercase && ruleLowercase && ruleNumber && ruleSpecial
    }
    
    private var passwordStrengthScore: Int {
        var score = 0
        if ruleLength { score += 1 }
        if ruleUppercase { score += 1 }
        if ruleLowercase { score += 1 }
        if ruleNumber { score += 1 }
        if ruleSpecial { score += 1 }
        return score
    }
    
    private var passwordStrengthText: String {
        switch passwordStrengthScore {
        case 0...2: return "Weak"
        case 3: return "Fair"
        case 4: return "Strong"
        case 5: return "Very Strong"
        default: return "Weak"
        }
    }
    
    private var passwordStrengthColor: Color {
        switch passwordStrengthScore {
        case 0...2: return Color(red: 225/255, green: 29/255, blue: 72/255)
        case 3: return Color(red: 234/255, green: 179/255, blue: 8/255)
        case 4: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case 5: return Color(red: 15/255, green: 90/255, blue: 71/255)
        default: return Color(red: 225/255, green: 29/255, blue: 72/255)
        }
    }
    
    private var parsedAge: Int? { Int(age.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var isEmailValid: Bool {
        normalizedEmail.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
    private var isAgeValid: Bool {
        guard let a = parsedAge else { return false }
        return a >= 16 && a <= 100
    }
    
    private var isFormValidForSignUp: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isAgeValid &&
        isEmailValid &&
        passwordSatisfiesAllRules &&
        password == confirmPassword
    }

    private var isFormValidForLogin: Bool {
        isEmailValid && !password.isEmpty
    }

    private func handleAuthSubmit() {
        Haptics.selection()
        Task {
            let success: Bool
            if isSignUp {
                guard isFormValidForSignUp else { return }
                let trimmedEmail = normalizedEmail
                let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                success = await auth.signUp(email: trimmedEmail, password: password, fullName: trimmedName, age: parsedAge)
                if success {
                    app.onboardingStep = 0
                    app.route = .onboarding
                }
            } else {
                guard isFormValidForLogin else { return }
                let trimmedEmail = normalizedEmail
                success = await auth.signIn(email: trimmedEmail, password: password)
                if success {
                    if auth.isOnboardingCompleted(for: auth.currentUserId) {
                        app.route = .main
                    } else {
                        app.onboardingStep = 0
                        app.route = .onboarding
                    }
                }
            }
        }
    }

    var body: some View {
        ZStack {
            offWhiteBackground
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Top Brand Header
                    HStack(spacing: 8) {
                        MockexaLogoIcon()
                            .scaleEffect(0.65)
                            .frame(width: 26, height: 26)
                        
                        Text("MOCKEXA")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(darkNavy)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 16)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    .offset(y: appearAnimation || reduceMotion ? 0 : -8)
                    
                    Spacer(minLength: 20)
                    
                    // Welcome Text Area
                    VStack(alignment: .leading, spacing: 6) {
                        Text(isSignUp ? "Create Account" : "Welcome to Mockexa")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(darkNavy)
                        
                        Text(isSignUp ? "Start your placement preparation today." : "Sign in to continue your interview preparation.")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(subtextSlate)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    .offset(y: appearAnimation || reduceMotion ? 0 : 10)
                    
                    if let error = auth.authError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 159/255, green: 18/255, blue: 57/255))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 255/255, green: 241/255, blue: 242/255), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 254/255, green: 205/255, blue: 211/255)))
                        .padding(.horizontal, 28)
                        .padding(.top, 16)
                    }
                    
                    Spacer(minLength: 24)
                    
                    // Main Direct Form: Full Name, Email, Password, Requirements, Confirm Password
                    VStack(spacing: 16) {
                        // Full Name Field (Sign Up Only)
                        if isSignUp {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Full Name")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(darkNavy)
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(emeraldColor)
                                    
                                    TextField("", text: $fullName, prompt: Text("Enter your full name").foregroundStyle(subtextSlate))
                                        .textInputAutocapitalization(.words)
                                        .font(.system(size: 16))
                                        .foregroundStyle(darkNavy)
                                        .focused($focusedField, equals: .fullName)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .age }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                                .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Full Name")
                            
                            // Age Field (Sign Up Only)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Age")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(darkNavy)
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "number")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(emeraldColor)
                                    
                                    TextField("", text: $age, prompt: Text("Enter your age (e.g. 21)").foregroundStyle(subtextSlate))
                                        .keyboardType(.numberPad)
                                        .font(.system(size: 16))
                                        .foregroundStyle(darkNavy)
                                        .focused($focusedField, equals: .age)
                                        .submitLabel(.next)
                                        .onSubmit { focusedField = .email }
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                                .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                                
                                if !age.isEmpty && !isAgeValid {
                                    Text("Please enter a valid age between 16 and 100.")
                                        .font(.caption)
                                        .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Age")
                        }
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(darkNavy)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(emeraldColor)
                                
                                TextField("", text: $email, prompt: Text("Enter your email").foregroundStyle(subtextSlate))
                                    .textContentType(.emailAddress)
                                    .keyboardType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .font(.system(size: 16))
                                    .foregroundStyle(darkNavy)
                                    .focused($focusedField, equals: .email)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Email address")

                        if !email.isEmpty && !isEmailValid {
                            Text("Enter a valid email address.")
                                .font(.caption)
                                .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        // Password Field
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(darkNavy)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(emeraldColor)
                                
                                Group {
                                    if showPassword {
                                        TextField("", text: $password, prompt: Text("Enter your password").foregroundStyle(subtextSlate))
                                            .font(.system(size: 16))
                                            .foregroundStyle(darkNavy)
                                            .focused($focusedField, equals: .password)
                                            .submitLabel(isSignUp ? .next : .go)
                                            .onSubmit {
                                                if isSignUp {
                                                    focusedField = .confirmPassword
                                                } else {
                                                    handleAuthSubmit()
                                                }
                                            }
                                    } else {
                                        SecureField("", text: $password, prompt: Text("Enter your password").foregroundStyle(subtextSlate))
                                            .font(.system(size: 16))
                                            .foregroundStyle(darkNavy)
                                            .focused($focusedField, equals: .password)
                                            .submitLabel(isSignUp ? .next : .go)
                                            .onSubmit {
                                                if isSignUp {
                                                    focusedField = .confirmPassword
                                                } else {
                                                    handleAuthSubmit()
                                                }
                                            }
                                    }
                                }
                                
                                Button {
                                    Haptics.selection()
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.fill" : "eye.slash.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(subtextSlate)
                                        .padding(4)
                                }
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Password")
                        
                        // Live Password Requirements & Strength Meter (Sign Up Only)
                        if isSignUp && !password.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Password strength:")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(subtextSlate)
                                    Text(passwordStrengthText)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(passwordStrengthColor)
                                    Spacer()
                                }
                                
                                HStack(spacing: 4) {
                                    ForEach(1...5, id: \.self) { idx in
                                        Capsule()
                                            .fill(idx <= passwordStrengthScore ? passwordStrengthColor : Color(red: 226/255, green: 232/255, blue: 240/255))
                                            .frame(height: 4)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Password requirements:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(subtextSlate)
                                        .padding(.top, 2)
                                    
                                    RequirementRow(satisfied: ruleLength, text: "At least 8 characters")
                                    RequirementRow(satisfied: ruleUppercase, text: "One uppercase letter")
                                    RequirementRow(satisfied: ruleLowercase, text: "One lowercase letter")
                                    RequirementRow(satisfied: ruleNumber, text: "One number")
                                    RequirementRow(satisfied: ruleSpecial, text: "One special character")
                                }
                            }
                            .padding(12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                        }
                        
                        // Confirm Password Field (Sign Up Only)
                        if isSignUp {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Confirm Password")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(darkNavy)
                                
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(emeraldColor)
                                    
                                    Group {
                                        if showConfirmPassword {
                                            TextField("", text: $confirmPassword, prompt: Text("Re-enter your password").foregroundStyle(subtextSlate))
                                                .font(.system(size: 16))
                                                .foregroundStyle(darkNavy)
                                                .focused($focusedField, equals: .confirmPassword)
                                                .submitLabel(.done)
                                                .onSubmit { handleAuthSubmit() }
                                        } else {
                                            SecureField("", text: $confirmPassword, prompt: Text("Re-enter your password").foregroundStyle(subtextSlate))
                                                .font(.system(size: 16))
                                                .foregroundStyle(darkNavy)
                                                .focused($focusedField, equals: .confirmPassword)
                                                .submitLabel(.done)
                                                .onSubmit { handleAuthSubmit() }
                                        }
                                    }
                                    
                                    Button {
                                        Haptics.selection()
                                        showConfirmPassword.toggle()
                                    } label: {
                                        Image(systemName: showConfirmPassword ? "eye.fill" : "eye.slash.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(subtextSlate)
                                            .padding(4)
                                    }
                                    .accessibilityLabel(showConfirmPassword ? "Hide confirm password" : "Show confirm password")
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 54)
                                .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Confirm Password")
                            
                            if !password.isEmpty && !confirmPassword.isEmpty {
                                HStack(spacing: 6) {
                                    if password == confirmPassword {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(emeraldColor)
                                        Text("Passwords match")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(emeraldColor)
                                    } else {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                                        Text("Passwords do not match")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        
                        // Forgot Password Link (Log In Only)
                        if !isSignUp {
                            HStack {
                                Spacer()
                                Button {
                                    Haptics.selection()
                                    if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        auth.authError = "Please enter your email above to reset password."
                                    } else {
                                        Task {
                                            let success = await auth.sendPasswordReset(email: email)
                                            if success {
                                                forgotSuccessMessage = "A password recovery email has been sent to \(email). Please check your inbox."
                                                showForgotAlert = true
                                            }
                                        }
                                    }
                                } label: {
                                    Text("Forgot Password?")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(emeraldColor)
                                }
                                .accessibilityLabel("Forgot password")
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 28)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    .offset(y: appearAnimation || reduceMotion ? 0 : 12)
                    
                    Spacer(minLength: 20)
                    
                    // Main CTA Button (Sign Up / Log In)
                    Button {
                        handleAuthSubmit()
                    } label: {
                        HStack {
                            Spacer()
                            Text(auth.isLoading ? (isSignUp ? "Creating account…" : "Authenticating…") : (isSignUp ? "Sign Up" : "Log In"))
                                .font(.system(size: 17, weight: .bold))
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .frame(height: 56)
                        .background(
                            LinearGradient(
                                colors: [
                                    emeraldColor,
                                    Color(red: 10/255, green: 75/255, blue: 58/255)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 28)
                        )
                        .shadow(color: emeraldColor.opacity(0.3), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(GetStartedButtonStyle())
                    .disabled(isSignUp ? (!isFormValidForSignUp || auth.isLoading) : (!isFormValidForLogin || auth.isLoading))
                    .opacity((isSignUp ? isFormValidForSignUp : isFormValidForLogin) && !auth.isLoading ? 1.0 : 0.6)
                    .padding(.horizontal, 28)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    .offset(y: appearAnimation || reduceMotion ? 0 : 14)
                    
                    Spacer(minLength: 22)
                    
                    // OR Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(Color(red: 226/255, green: 232/255, blue: 240/255))
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(subtextSlate)
                        
                        Rectangle()
                            .fill(Color(red: 226/255, green: 232/255, blue: 240/255))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 28)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    
                    Spacer(minLength: 20)
                    
                    // Only show providers that are configured for this Supabase project.
                    HStack(spacing: 14) {
                        CompactProviderButton(
                            label: "Google",
                            accessibilityLabel: "Continue with Google"
                        ) {
                            GoogleGLogo()
                                .scaleEffect(0.8)
                        } action: {
                            Task {
                                let success = await auth.signInWithGoogle()
                                if success {
                                    if auth.isOnboardingCompleted(for: auth.currentUserId) {
                                        app.route = .main
                                    } else {
                                        app.onboardingStep = 0
                                        app.route = .onboarding
                                    }
                                }
                            }
                        }
                        
                        CompactProviderButton(
                            label: "Phone",
                            accessibilityLabel: "Sign in with phone"
                        ) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(emeraldColor)
                        } action: {
                            showPhone = true
                        }
                    }
                    .padding(.horizontal, 28)
                    .opacity(appearAnimation || reduceMotion ? 1 : 0)
                    
                    Spacer(minLength: 24)
                    
                    // Account Switcher Link
                    Button {
                        Haptics.selection()
                        auth.authError = nil
                        withAnimation { isSignUp.toggle() }
                    } label: {
                        Text(isSignUp ? "Already have an account? Log In" : "Need an account? Sign Up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(emeraldColor)
                    }
                    
                    Spacer(minLength: 20)
                    
                    // Footer Terms & Privacy Notice
                    Text("By signing in, you agree to our Terms & Privacy Policy")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(subtextSlate.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)
                }
            }
        }
        .alert("Password Reset", isPresented: $showForgotAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(forgotSuccessMessage ?? "If an account exists for this email, a password recovery email will be sent.")
        }
        .sheet(isPresented: $showPhone) {
            PhoneAuthView()
                .environmentObject(app)
                .environmentObject(auth)
                .presentationDetents([.fraction(0.6), .large])
                .presentationCornerRadius(30)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                appearAnimation = true
            }
        }
    }
}



// MARK: - Country Code Data Model
struct CountryCode: Identifiable, Hashable {
    let id: String
    let name: String
    let dialCode: String
    let isoCode: String
    
    var flag: String {
        let base: UInt32 = 127397
        var s = ""
        for v in isoCode.uppercased().unicodeScalars {
            if v.value >= 65 && v.value <= 90, let scalar = UnicodeScalar(base + v.value) {
                s.unicodeScalars.append(scalar)
            }
        }
        return s.isEmpty ? "🌐" : s
    }
    
    static let defaultCountry = CountryCode(id: "IN", name: "India", dialCode: "+91", isoCode: "IN")
    
    static let allCountries: [CountryCode] = [
        CountryCode(id: "AF", name: "Afghanistan", dialCode: "+93", isoCode: "AF"),
        CountryCode(id: "AL", name: "Albania", dialCode: "+355", isoCode: "AL"),
        CountryCode(id: "DZ", name: "Algeria", dialCode: "+213", isoCode: "DZ"),
        CountryCode(id: "AS", name: "American Samoa", dialCode: "+1684", isoCode: "AS"),
        CountryCode(id: "AD", name: "Andorra", dialCode: "+376", isoCode: "AD"),
        CountryCode(id: "AO", name: "Angola", dialCode: "+244", isoCode: "AO"),
        CountryCode(id: "AI", name: "Anguilla", dialCode: "+1264", isoCode: "AI"),
        CountryCode(id: "AG", name: "Antigua and Barbuda", dialCode: "+1268", isoCode: "AG"),
        CountryCode(id: "AR", name: "Argentina", dialCode: "+54", isoCode: "AR"),
        CountryCode(id: "AM", name: "Armenia", dialCode: "+374", isoCode: "AM"),
        CountryCode(id: "AW", name: "Aruba", dialCode: "+297", isoCode: "AW"),
        CountryCode(id: "AU", name: "Australia", dialCode: "+61", isoCode: "AU"),
        CountryCode(id: "AT", name: "Austria", dialCode: "+43", isoCode: "AT"),
        CountryCode(id: "AZ", name: "Azerbaijan", dialCode: "+994", isoCode: "AZ"),
        CountryCode(id: "BS", name: "Bahamas", dialCode: "+1242", isoCode: "BS"),
        CountryCode(id: "BH", name: "Bahrain", dialCode: "+973", isoCode: "BH"),
        CountryCode(id: "BD", name: "Bangladesh", dialCode: "+880", isoCode: "BD"),
        CountryCode(id: "BB", name: "Barbados", dialCode: "+1246", isoCode: "BB"),
        CountryCode(id: "BY", name: "Belarus", dialCode: "+375", isoCode: "BY"),
        CountryCode(id: "BE", name: "Belgium", dialCode: "+32", isoCode: "BE"),
        CountryCode(id: "BZ", name: "Belize", dialCode: "+501", isoCode: "BZ"),
        CountryCode(id: "BJ", name: "Benin", dialCode: "+229", isoCode: "BJ"),
        CountryCode(id: "BM", name: "Bermuda", dialCode: "+1441", isoCode: "BM"),
        CountryCode(id: "BT", name: "Bhutan", dialCode: "+975", isoCode: "BT"),
        CountryCode(id: "BO", name: "Bolivia", dialCode: "+591", isoCode: "BO"),
        CountryCode(id: "BA", name: "Bosnia and Herzegovina", dialCode: "+387", isoCode: "BA"),
        CountryCode(id: "BW", name: "Botswana", dialCode: "+267", isoCode: "BW"),
        CountryCode(id: "BR", name: "Brazil", dialCode: "+55", isoCode: "BR"),
        CountryCode(id: "VG", name: "British Virgin Islands", dialCode: "+1284", isoCode: "VG"),
        CountryCode(id: "BN", name: "Brunei", dialCode: "+673", isoCode: "BN"),
        CountryCode(id: "BG", name: "Bulgaria", dialCode: "+359", isoCode: "BG"),
        CountryCode(id: "BF", name: "Burkina Faso", dialCode: "+226", isoCode: "BF"),
        CountryCode(id: "BI", name: "Burundi", dialCode: "+257", isoCode: "BI"),
        CountryCode(id: "KH", name: "Cambodia", dialCode: "+855", isoCode: "KH"),
        CountryCode(id: "CM", name: "Cameroon", dialCode: "+237", isoCode: "CM"),
        CountryCode(id: "CA", name: "Canada", dialCode: "+1", isoCode: "CA"),
        CountryCode(id: "CV", name: "Cape Verde", dialCode: "+238", isoCode: "CV"),
        CountryCode(id: "KY", name: "Cayman Islands", dialCode: "+1345", isoCode: "KY"),
        CountryCode(id: "CF", name: "Central African Republic", dialCode: "+236", isoCode: "CF"),
        CountryCode(id: "TD", name: "Chad", dialCode: "+235", isoCode: "TD"),
        CountryCode(id: "CL", name: "Chile", dialCode: "+56", isoCode: "CL"),
        CountryCode(id: "CN", name: "China", dialCode: "+86", isoCode: "CN"),
        CountryCode(id: "CO", name: "Colombia", dialCode: "+57", isoCode: "CO"),
        CountryCode(id: "KM", name: "Comoros", dialCode: "+269", isoCode: "KM"),
        CountryCode(id: "CG", name: "Congo", dialCode: "+242", isoCode: "CG"),
        CountryCode(id: "CD", name: "Congo (DRC)", dialCode: "+243", isoCode: "CD"),
        CountryCode(id: "CK", name: "Cook Islands", dialCode: "+682", isoCode: "CK"),
        CountryCode(id: "CR", name: "Costa Rica", dialCode: "+506", isoCode: "CR"),
        CountryCode(id: "HR", name: "Croatia", dialCode: "+385", isoCode: "HR"),
        CountryCode(id: "CU", name: "Cuba", dialCode: "+53", isoCode: "CU"),
        CountryCode(id: "CY", name: "Cyprus", dialCode: "+357", isoCode: "CY"),
        CountryCode(id: "CZ", name: "Czech Republic", dialCode: "+420", isoCode: "CZ"),
        CountryCode(id: "DK", name: "Denmark", dialCode: "+45", isoCode: "DK"),
        CountryCode(id: "DJ", name: "Djibouti", dialCode: "+253", isoCode: "DJ"),
        CountryCode(id: "DM", name: "Dominica", dialCode: "+1767", isoCode: "DM"),
        CountryCode(id: "DO", name: "Dominican Republic", dialCode: "+1809", isoCode: "DO"),
        CountryCode(id: "EC", name: "Ecuador", dialCode: "+593", isoCode: "EC"),
        CountryCode(id: "EG", name: "Egypt", dialCode: "+20", isoCode: "EG"),
        CountryCode(id: "SV", name: "El Salvador", dialCode: "+503", isoCode: "SV"),
        CountryCode(id: "GQ", name: "Equatorial Guinea", dialCode: "+240", isoCode: "GQ"),
        CountryCode(id: "ER", name: "Eritrea", dialCode: "+291", isoCode: "ER"),
        CountryCode(id: "EE", name: "Estonia", dialCode: "+372", isoCode: "EE"),
        CountryCode(id: "SZ", name: "Eswatini", dialCode: "+268", isoCode: "SZ"),
        CountryCode(id: "ET", name: "Ethiopia", dialCode: "+251", isoCode: "ET"),
        CountryCode(id: "FJ", name: "Fiji", dialCode: "+679", isoCode: "FJ"),
        CountryCode(id: "FI", name: "Finland", dialCode: "+358", isoCode: "FI"),
        CountryCode(id: "FR", name: "France", dialCode: "+33", isoCode: "FR"),
        CountryCode(id: "GF", name: "French Guiana", dialCode: "+594", isoCode: "GF"),
        CountryCode(id: "PF", name: "French Polynesia", dialCode: "+689", isoCode: "PF"),
        CountryCode(id: "GA", name: "Gabon", dialCode: "+241", isoCode: "GA"),
        CountryCode(id: "GM", name: "Gambia", dialCode: "+220", isoCode: "GM"),
        CountryCode(id: "GE", name: "Georgia", dialCode: "+995", isoCode: "GE"),
        CountryCode(id: "DE", name: "Germany", dialCode: "+49", isoCode: "DE"),
        CountryCode(id: "GH", name: "Ghana", dialCode: "+233", isoCode: "GH"),
        CountryCode(id: "GI", name: "Gibraltar", dialCode: "+350", isoCode: "GI"),
        CountryCode(id: "GR", name: "Greece", dialCode: "+30", isoCode: "GR"),
        CountryCode(id: "GL", name: "Greenland", dialCode: "+299", isoCode: "GL"),
        CountryCode(id: "GD", name: "Grenada", dialCode: "+1473", isoCode: "GD"),
        CountryCode(id: "GP", name: "Guadeloupe", dialCode: "+590", isoCode: "GP"),
        CountryCode(id: "GU", name: "Guam", dialCode: "+1671", isoCode: "GU"),
        CountryCode(id: "GT", name: "Guatemala", dialCode: "+502", isoCode: "GT"),
        CountryCode(id: "GN", name: "Guinea", dialCode: "+224", isoCode: "GN"),
        CountryCode(id: "GW", name: "Guinea-Bissau", dialCode: "+245", isoCode: "GW"),
        CountryCode(id: "GY", name: "Guyana", dialCode: "+592", isoCode: "GY"),
        CountryCode(id: "HT", name: "Haiti", dialCode: "+509", isoCode: "HT"),
        CountryCode(id: "HN", name: "Honduras", dialCode: "+504", isoCode: "HN"),
        CountryCode(id: "HK", name: "Hong Kong", dialCode: "+852", isoCode: "HK"),
        CountryCode(id: "HU", name: "Hungary", dialCode: "+36", isoCode: "HU"),
        CountryCode(id: "IS", name: "Iceland", dialCode: "+354", isoCode: "IS"),
        CountryCode(id: "IN", name: "India", dialCode: "+91", isoCode: "IN"),
        CountryCode(id: "ID", name: "Indonesia", dialCode: "+62", isoCode: "ID"),
        CountryCode(id: "IR", name: "Iran", dialCode: "+98", isoCode: "IR"),
        CountryCode(id: "IQ", name: "Iraq", dialCode: "+964", isoCode: "IQ"),
        CountryCode(id: "IE", name: "Ireland", dialCode: "+353", isoCode: "IE"),
        CountryCode(id: "IL", name: "Israel", dialCode: "+972", isoCode: "IL"),
        CountryCode(id: "IT", name: "Italy", dialCode: "+39", isoCode: "IT"),
        CountryCode(id: "CI", name: "Ivory Coast", dialCode: "+225", isoCode: "CI"),
        CountryCode(id: "JM", name: "Jamaica", dialCode: "+1876", isoCode: "JM"),
        CountryCode(id: "JP", name: "Japan", dialCode: "+81", isoCode: "JP"),
        CountryCode(id: "JO", name: "Jordan", dialCode: "+962", isoCode: "JO"),
        CountryCode(id: "KZ", name: "Kazakhstan", dialCode: "+7", isoCode: "KZ"),
        CountryCode(id: "KE", name: "Kenya", dialCode: "+254", isoCode: "KE"),
        CountryCode(id: "KI", name: "Kiribati", dialCode: "+686", isoCode: "KI"),
        CountryCode(id: "XK", name: "Kosovo", dialCode: "+383", isoCode: "XK"),
        CountryCode(id: "KW", name: "Kuwait", dialCode: "+965", isoCode: "KW"),
        CountryCode(id: "KG", name: "Kyrgyzstan", dialCode: "+996", isoCode: "KG"),
        CountryCode(id: "LA", name: "Laos", dialCode: "+856", isoCode: "LA"),
        CountryCode(id: "LV", name: "Latvia", dialCode: "+371", isoCode: "LV"),
        CountryCode(id: "LB", name: "Lebanon", dialCode: "+961", isoCode: "LB"),
        CountryCode(id: "LS", name: "Lesotho", dialCode: "+266", isoCode: "LS"),
        CountryCode(id: "LR", name: "Liberia", dialCode: "+231", isoCode: "LR"),
        CountryCode(id: "LY", name: "Libya", dialCode: "+218", isoCode: "LY"),
        CountryCode(id: "LI", name: "Liechtenstein", dialCode: "+423", isoCode: "LI"),
        CountryCode(id: "LT", name: "Lithuania", dialCode: "+370", isoCode: "LT"),
        CountryCode(id: "LU", name: "Luxembourg", dialCode: "+352", isoCode: "LU"),
        CountryCode(id: "MO", name: "Macao", dialCode: "+853", isoCode: "MO"),
        CountryCode(id: "MG", name: "Madagascar", dialCode: "+261", isoCode: "MG"),
        CountryCode(id: "MW", name: "Malawi", dialCode: "+265", isoCode: "MW"),
        CountryCode(id: "MY", name: "Malaysia", dialCode: "+60", isoCode: "MY"),
        CountryCode(id: "MV", name: "Maldives", dialCode: "+960", isoCode: "MV"),
        CountryCode(id: "ML", name: "Mali", dialCode: "+223", isoCode: "ML"),
        CountryCode(id: "MT", name: "Malta", dialCode: "+356", isoCode: "MT"),
        CountryCode(id: "MH", name: "Marshall Islands", dialCode: "+692", isoCode: "MH"),
        CountryCode(id: "MQ", name: "Martinique", dialCode: "+596", isoCode: "MQ"),
        CountryCode(id: "MR", name: "Mauritania", dialCode: "+222", isoCode: "MR"),
        CountryCode(id: "MU", name: "Mauritius", dialCode: "+230", isoCode: "MU"),
        CountryCode(id: "MX", name: "Mexico", dialCode: "+52", isoCode: "MX"),
        CountryCode(id: "FM", name: "Micronesia", dialCode: "+691", isoCode: "FM"),
        CountryCode(id: "MD", name: "Moldova", dialCode: "+373", isoCode: "MD"),
        CountryCode(id: "MC", name: "Monaco", dialCode: "+377", isoCode: "MC"),
        CountryCode(id: "MN", name: "Mongolia", dialCode: "+976", isoCode: "MN"),
        CountryCode(id: "ME", name: "Montenegro", dialCode: "+382", isoCode: "ME"),
        CountryCode(id: "MS", name: "Montserrat", dialCode: "+1664", isoCode: "MS"),
        CountryCode(id: "MA", name: "Morocco", dialCode: "+212", isoCode: "MA"),
        CountryCode(id: "MZ", name: "Mozambique", dialCode: "+258", isoCode: "MZ"),
        CountryCode(id: "MM", name: "Myanmar", dialCode: "+95", isoCode: "MM"),
        CountryCode(id: "NA", name: "Namibia", dialCode: "+264", isoCode: "NA"),
        CountryCode(id: "NR", name: "Nauru", dialCode: "+674", isoCode: "NR"),
        CountryCode(id: "NP", name: "Nepal", dialCode: "+977", isoCode: "NP"),
        CountryCode(id: "NL", name: "Netherlands", dialCode: "+31", isoCode: "NL"),
        CountryCode(id: "NC", name: "New Caledonia", dialCode: "+687", isoCode: "NC"),
        CountryCode(id: "NZ", name: "New Zealand", dialCode: "+64", isoCode: "NZ"),
        CountryCode(id: "NI", name: "Nicaragua", dialCode: "+505", isoCode: "NI"),
        CountryCode(id: "NE", name: "Niger", dialCode: "+227", isoCode: "NE"),
        CountryCode(id: "NG", name: "Nigeria", dialCode: "+234", isoCode: "NG"),
        CountryCode(id: "KP", name: "North Korea", dialCode: "+850", isoCode: "KP"),
        CountryCode(id: "MK", name: "North Macedonia", dialCode: "+389", isoCode: "MK"),
        CountryCode(id: "NO", name: "Norway", dialCode: "+47", isoCode: "NO"),
        CountryCode(id: "OM", name: "Oman", dialCode: "+968", isoCode: "OM"),
        CountryCode(id: "PK", name: "Pakistan", dialCode: "+92", isoCode: "PK"),
        CountryCode(id: "PW", name: "Palau", dialCode: "+680", isoCode: "PW"),
        CountryCode(id: "PS", name: "Palestine", dialCode: "+970", isoCode: "PS"),
        CountryCode(id: "PA", name: "Panama", dialCode: "+507", isoCode: "PA"),
        CountryCode(id: "PG", name: "Papua New Guinea", dialCode: "+675", isoCode: "PG"),
        CountryCode(id: "PY", name: "Paraguay", dialCode: "+595", isoCode: "PY"),
        CountryCode(id: "PE", name: "Peru", dialCode: "+51", isoCode: "PE"),
        CountryCode(id: "PH", name: "Philippines", dialCode: "+63", isoCode: "PH"),
        CountryCode(id: "PL", name: "Poland", dialCode: "+48", isoCode: "PL"),
        CountryCode(id: "PT", name: "Portugal", dialCode: "+351", isoCode: "PT"),
        CountryCode(id: "PR", name: "Puerto Rico", dialCode: "+1787", isoCode: "PR"),
        CountryCode(id: "QA", name: "Qatar", dialCode: "+974", isoCode: "QA"),
        CountryCode(id: "RO", name: "Romania", dialCode: "+40", isoCode: "RO"),
        CountryCode(id: "RU", name: "Russia", dialCode: "+7", isoCode: "RU"),
        CountryCode(id: "RW", name: "Rwanda", dialCode: "+250", isoCode: "RW"),
        CountryCode(id: "WS", name: "Samoa", dialCode: "+685", isoCode: "WS"),
        CountryCode(id: "SM", name: "San Marino", dialCode: "+378", isoCode: "SM"),
        CountryCode(id: "SA", name: "Saudi Arabia", dialCode: "+966", isoCode: "SA"),
        CountryCode(id: "SN", name: "Senegal", dialCode: "+221", isoCode: "SN"),
        CountryCode(id: "RS", name: "Serbia", dialCode: "+381", isoCode: "RS"),
        CountryCode(id: "SC", name: "Seychelles", dialCode: "+248", isoCode: "SC"),
        CountryCode(id: "SL", name: "Sierra Leone", dialCode: "+232", isoCode: "SL"),
        CountryCode(id: "SG", name: "Singapore", dialCode: "+65", isoCode: "SG"),
        CountryCode(id: "SK", name: "Slovakia", dialCode: "+421", isoCode: "SK"),
        CountryCode(id: "SI", name: "Slovenia", dialCode: "+386", isoCode: "SI"),
        CountryCode(id: "SB", name: "Solomon Islands", dialCode: "+677", isoCode: "SB"),
        CountryCode(id: "SO", name: "Somalia", dialCode: "+252", isoCode: "SO"),
        CountryCode(id: "ZA", name: "South Africa", dialCode: "+27", isoCode: "ZA"),
        CountryCode(id: "KR", name: "South Korea", dialCode: "+82", isoCode: "KR"),
        CountryCode(id: "SS", name: "South Sudan", dialCode: "+211", isoCode: "SS"),
        CountryCode(id: "ES", name: "Spain", dialCode: "+34", isoCode: "ES"),
        CountryCode(id: "LK", name: "Sri Lanka", dialCode: "+94", isoCode: "LK"),
        CountryCode(id: "SD", name: "Sudan", dialCode: "+249", isoCode: "SD"),
        CountryCode(id: "SR", name: "Suriname", dialCode: "+597", isoCode: "SR"),
        CountryCode(id: "SE", name: "Sweden", dialCode: "+46", isoCode: "SE"),
        CountryCode(id: "CH", name: "Switzerland", dialCode: "+41", isoCode: "CH"),
        CountryCode(id: "SY", name: "Syria", dialCode: "+963", isoCode: "SY"),
        CountryCode(id: "TW", name: "Taiwan", dialCode: "+886", isoCode: "TW"),
        CountryCode(id: "TJ", name: "Tajikistan", dialCode: "+992", isoCode: "TJ"),
        CountryCode(id: "TZ", name: "Tanzania", dialCode: "+255", isoCode: "TZ"),
        CountryCode(id: "TH", name: "Thailand", dialCode: "+66", isoCode: "TH"),
        CountryCode(id: "TL", name: "Timor-Leste", dialCode: "+670", isoCode: "TL"),
        CountryCode(id: "TG", name: "Togo", dialCode: "+228", isoCode: "TG"),
        CountryCode(id: "TO", name: "Tonga", dialCode: "+676", isoCode: "TO"),
        CountryCode(id: "TT", name: "Trinidad and Tobago", dialCode: "+1868", isoCode: "TT"),
        CountryCode(id: "TN", name: "Tunisia", dialCode: "+216", isoCode: "TN"),
        CountryCode(id: "TR", name: "Turkey", dialCode: "+90", isoCode: "TR"),
        CountryCode(id: "TM", name: "Turkmenistan", dialCode: "+993", isoCode: "TM"),
        CountryCode(id: "TC", name: "Turks and Caicos", dialCode: "+1649", isoCode: "TC"),
        CountryCode(id: "TV", name: "Tuvalu", dialCode: "+688", isoCode: "TV"),
        CountryCode(id: "UG", name: "Uganda", dialCode: "+256", isoCode: "UG"),
        CountryCode(id: "UA", name: "Ukraine", dialCode: "+380", isoCode: "UA"),
        CountryCode(id: "AE", name: "United Arab Emirates", dialCode: "+971", isoCode: "AE"),
        CountryCode(id: "GB", name: "United Kingdom", dialCode: "+44", isoCode: "GB"),
        CountryCode(id: "US", name: "United States", dialCode: "+1", isoCode: "US"),
        CountryCode(id: "UY", name: "Uruguay", dialCode: "+598", isoCode: "UY"),
        CountryCode(id: "UZ", name: "Uzbekistan", dialCode: "+998", isoCode: "UZ"),
        CountryCode(id: "VU", name: "Vanuatu", dialCode: "+678", isoCode: "VU"),
        CountryCode(id: "VA", name: "Vatican City", dialCode: "+39", isoCode: "VA"),
        CountryCode(id: "VE", name: "Venezuela", dialCode: "+58", isoCode: "VE"),
        CountryCode(id: "VN", name: "Vietnam", dialCode: "+84", isoCode: "VN"),
        CountryCode(id: "YE", name: "Yemen", dialCode: "+967", isoCode: "YE"),
        CountryCode(id: "ZM", name: "Zambia", dialCode: "+260", isoCode: "ZM"),
        CountryCode(id: "ZW", name: "Zimbabwe", dialCode: "+263", isoCode: "ZW")
    ]
}

// MARK: - Country Code Selection Sheet
struct CountryPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCountry: CountryCode
    
    @State private var searchText = ""
    
    private let darkNavy = Color(red: 15/255, green: 23/255, blue: 42/255)
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let subtextSlate = Color(red: 100/255, green: 116/255, blue: 139/255)
    private let inputBg = Color(red: 241/255, green: 245/255, blue: 249/255)
    
    private var filteredCountries: [CountryCode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return CountryCode.allCountries
        }
        return CountryCode.allCountries.filter { country in
            country.name.lowercased().contains(query) ||
            country.isoCode.lowercased().contains(query) ||
            country.dialCode.lowercased().contains(query) ||
            country.dialCode.replacingOccurrences(of: "+", with: "").contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar Header
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(subtextSlate)
                    
                    TextField("Search country, code, or +dialing", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundStyle(darkNavy)
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(subtextSlate)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(inputBg, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // Country List
                List(filteredCountries) { country in
                    Button {
                        Haptics.selection()
                        selectedCountry = country
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(country.flag)
                                .font(.system(size: 24))
                            
                            Text(country.name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(darkNavy)
                            
                            Spacer()
                            
                            Text(country.dialCode)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(country == selectedCountry ? emeraldColor : subtextSlate)
                            
                            if country == selectedCountry {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(emeraldColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(country.name), plus \(country.dialCode.replacingOccurrences(of: "+", with: ""))")
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(emeraldColor)
                }
            }
        }
    }
}

// MARK: - Phone Authentication View
struct PhoneAuthView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    @Environment(\.dismiss) var dismiss
    
    enum Step { case enterPhone, verifyOTP }
    
    @State private var step: Step = .enterPhone
    @State private var selectedCountry: CountryCode = CountryCode.defaultCountry
    @State private var phoneNumber = ""
    @State private var otpCode = ""
    @State private var showCountryPicker = false
    @State private var resendCooldown = 0
    @State private var phoneSuccessNotice: String? = nil
    @State private var cooldownTimer: Timer? = nil
    
    private let emeraldColor = Color(red: 15/255, green: 90/255, blue: 71/255)
    private let darkNavy = Color(red: 15/255, green: 23/255, blue: 42/255)
    private let subtextSlate = Color(red: 100/255, green: 116/255, blue: 139/255)
    private let inputBg = Color(red: 241/255, green: 245/255, blue: 249/255)
    
    private var formattedPhone: String {
        let digits = phoneNumber.filter { $0 >= "0" && $0 <= "9" }
        let dialDigits = selectedCountry.dialCode.dropFirst()
        let localDigits = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") && digits.hasPrefix(dialDigits)
            ? String(digits.dropFirst(dialDigits.count)) : digits
        return "\(selectedCountry.dialCode)\(localDigits)"
    }

    private var isPhoneValid: Bool {
        let nationalCount = formattedPhone.count - selectedCountry.dialCode.count
        let totalDigits = formattedPhone.count - 1
        if selectedCountry.isoCode == "IN" { return nationalCount == 10 }
        return nationalCount >= 7 && (8...15).contains(totalDigits)
    }

    private var isOTPValid: Bool {
        otpCode.count == 6 && otpCode.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private var nationalDigitLimit: Int {
        selectedCountry.isoCode == "IN" ? 10 : max(7, 15 - selectedCountry.dialCode.dropFirst().count)
    }

    private var phonePlaceholder: String {
        selectedCountry.isoCode == "IN" ? "98765 43210" : "Mobile number"
    }

    private var maskedPhone: String {
        let digits = formattedPhone.filter(\.isNumber)
        guard digits.count > 4 else { return formattedPhone }
        return "\(selectedCountry.dialCode) •••••• \(digits.suffix(4))"
    }
    
    private func startCooldown() {
        resendCooldown = 30
        cooldownTimer?.invalidate()
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if resendCooldown > 1 {
                resendCooldown -= 1
            } else {
                resendCooldown = 0
                cooldownTimer?.invalidate()
                cooldownTimer = nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 248/255, green: 250/255, blue: 252/255)
                    .ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 8) {
                        ForEach(0..<2, id: \.self) { index in
                            Capsule()
                                .fill(index <= (step == .enterPhone ? 0 : 1) ? emeraldColor : Color(red: 226/255, green: 232/255, blue: 240/255))
                                .frame(height: 5)
                        }
                    }
                    .accessibilityLabel(step == .enterPhone ? "Step 1 of 2, phone number" : "Step 2 of 2, verification code")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(step == .enterPhone ? "Phone Sign In" : "Enter Code")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(darkNavy)
                        
                        Text(step == .enterPhone ? "Enter your mobile number to receive a secure one-time code." : "We sent a 6-digit verification code to \(maskedPhone).")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(subtextSlate)
                    }
                    .padding(.top, 8)
                    
                    if let notice = phoneSuccessNotice {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color(red: 16/255, green: 185/255, blue: 129/255))
                            Text(notice)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 6/255, green: 95/255, blue: 70/255))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 236/255, green: 253/255, blue: 245/255), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 167/255, green: 243/255, blue: 208/255)))
                    }
                    
                    if let error = auth.authError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                            Text(error)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 159/255, green: 18/255, blue: 57/255))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 255/255, green: 241/255, blue: 242/255), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 254/255, green: 205/255, blue: 211/255)))
                    }
                    
                    if step == .enterPhone {
#if targetEnvironment(simulator)
                        Button {
                            if let unitedStates = CountryCode.allCountries.first(where: { $0.isoCode == "US" }) {
                                selectedCountry = unitedStates
                            }
                            phoneNumber = "2025550123"
                            auth.authError = nil
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "testtube.2")
                                    .font(.system(size: 18, weight: .bold))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Use free prototype login")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("No SMS sent • +1 202 555 0123")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .foregroundStyle(emeraldColor)
                            .padding(14)
                            .background(Color(red: 236/255, green: 253/255, blue: 245/255), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 167/255, green: 243/255, blue: 208/255)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use free prototype phone number")
#endif

                        HStack(spacing: 12) {
                            Button {
                                Haptics.selection()
                                showCountryPicker = true
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedCountry.flag)
                                        .font(.system(size: 20))
                                    Text(selectedCountry.dialCode)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .foregroundStyle(darkNavy)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(subtextSlate)
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 56)
                                .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                            }
                            .accessibilityLabel("Country code, \(selectedCountry.name) plus \(selectedCountry.dialCode.replacingOccurrences(of: "+", with: ""))")
                            
                            HStack(spacing: 10) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(emeraldColor)
                                
                                TextField(phonePlaceholder, text: $phoneNumber)
                                    .keyboardType(.phonePad)
                                    .textContentType(.telephoneNumber)
                                    .font(.system(size: 16))
                                    .foregroundStyle(darkNavy)
                                    .onChange(of: phoneNumber) { _, newValue in
                                        let digits = newValue.filter(\.isNumber)
                                        let dialDigits = String(selectedCountry.dialCode.dropFirst())
                                        let localDigits = newValue.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("+") && digits.hasPrefix(dialDigits)
                                            ? String(digits.dropFirst(dialDigits.count)) : digits
                                        phoneNumber = String(localDigits.prefix(nationalDigitLimit))
                                        auth.authError = nil
                                    }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                        }

                        if !phoneNumber.isEmpty && !isPhoneValid {
                            Text(selectedCountry.isoCode == "IN" ? "Enter a 10-digit mobile number." : "Enter a valid mobile number for this country code.")
                                .font(.caption)
                                .foregroundStyle(Color(red: 225/255, green: 29/255, blue: 72/255))
                        }
                        
                        Button {
                            Haptics.selection()
                            phoneSuccessNotice = nil
                            Task {
                                let success = await auth.sendPhoneOTP(phone: formattedPhone)
                                if success {
                                    phoneSuccessNotice = "Verification code sent to \(formattedPhone)"
                                    startCooldown()
                                    withAnimation { step = .verifyOTP }
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(auth.isLoading ? "Sending Code…" : "Send Code")
                                    .font(.system(size: 17, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [
                                        emeraldColor,
                                        Color(red: 10/255, green: 75/255, blue: 58/255)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 28)
                            )
                            .shadow(color: emeraldColor.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(GetStartedButtonStyle())
                        .disabled(!isPhoneValid || auth.isLoading)
                        .opacity(!isPhoneValid || auth.isLoading ? 0.6 : 1.0)

                        Label("We'll only use this number for secure sign-in. Standard SMS charges may apply.", systemImage: "lock.shield.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(subtextSlate)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
#if targetEnvironment(simulator)
                        if formattedPhone == AuthManager.prototypePhoneNumber {
                            Button {
                                otpCode = AuthManager.prototypePhoneOTP
                                auth.authError = nil
                            } label: {
                                Label("Fill prototype code \(AuthManager.prototypePhoneOTP)", systemImage: "wand.and.stars")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(emeraldColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(Color(red: 236/255, green: 253/255, blue: 245/255), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
#endif

                        HStack(spacing: 10) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(emeraldColor)
                            
                            TextField("6-digit code", text: $otpCode)
                                .keyboardType(.numberPad)
                                .textContentType(.oneTimeCode)
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundStyle(darkNavy)
                                .onChange(of: otpCode) { _, newValue in
                                    let digits = newValue.filter { $0 >= "0" && $0 <= "9" }
                                    otpCode = String(digits.prefix(6))
                                    auth.authError = nil
                                }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .background(inputBg, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(red: 226/255, green: 232/255, blue: 240/255)))
                        
                        Button {
                            Haptics.selection()
                            phoneSuccessNotice = nil
                            Task {
                                let success = await auth.verifyPhoneOTP(phone: formattedPhone, token: otpCode)
                                if success {
                                    dismiss()
                                    if auth.isOnboardingCompleted(for: auth.currentUserId) {
                                        app.route = .main
                                    } else {
                                        app.onboardingStep = 0
                                        app.route = .onboarding
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text(auth.isLoading ? "Verifying…" : "Verify & Continue")
                                    .font(.system(size: 17, weight: .bold))
                                Spacer()
                            }
                            .foregroundStyle(.white)
                            .frame(height: 56)
                            .background(
                                LinearGradient(
                                    colors: [
                                        emeraldColor,
                                        Color(red: 10/255, green: 75/255, blue: 58/255)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 28)
                            )
                            .shadow(color: emeraldColor.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .buttonStyle(GetStartedButtonStyle())
                        .disabled(!isOTPValid || auth.isLoading)
                        .opacity(!isOTPValid || auth.isLoading ? 0.6 : 1.0)
                        
                        HStack {
                            Button("Edit Phone Number") {
                                phoneSuccessNotice = nil
                                auth.authError = nil
                                otpCode = ""
                                withAnimation { step = .enterPhone }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(subtextSlate)
                            
                            Spacer()
                            
                            Button(resendCooldown > 0 ? "Resend Code (\(resendCooldown)s)" : "Resend Code") {
                                guard resendCooldown == 0 && !auth.isLoading else { return }
                                phoneSuccessNotice = nil
                                Task {
                                    let success = await auth.sendPhoneOTP(phone: formattedPhone)
                                    if success {
                                        phoneSuccessNotice = "Code sent again to \(formattedPhone)"
                                        startCooldown()
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(resendCooldown > 0 ? subtextSlate : emeraldColor)
                            .disabled(resendCooldown > 0 || auth.isLoading)
                        }
                    }
                    
                    Spacer()
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(emeraldColor)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(selectedCountry: $selectedCountry)
                    .presentationDetents([.large])
                    .presentationCornerRadius(30)
            }
            .onDisappear {
                cooldownTimer?.invalidate()
                auth.authError = nil
            }
            .onAppear { auth.authError = nil }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var auth: AuthManager
    @AppStorage("MOCKEXA_TARGET_ROLE") private var savedTargetRole = ""
    @AppStorage("MOCKEXA_TARGET_COMPANIES") private var savedTargetCompanies = ""
    @AppStorage("MOCKEXA_STUDY_FIELD") private var savedStudyField = ""
    @AppStorage("MOCKEXA_CONFIDENCE_LEVEL") private var savedConfidenceLevel = 1
    @State private var selections: [Int: String] = [:]
    @State private var companies = Set<String>()
    @State private var confidence = 1.0
    
    let steps = [
        ("What are you studying?", ["Computer Science", "Information Technology", "Electronics", "Mechanical", "Civil", "Other"]),
        ("What role are you aiming for?", ["Software Engineer", "Data Analyst", "Product Manager", "Business Analyst", "Other"])
    ]
    
    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 22) {
                HStack {
                    if app.onboardingStep > 0 {
                        Button {
                            withAnimation(.spring) { app.onboardingStep -= 1 }
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .font(.caption.bold())
                        }
                        .foregroundStyle(MockexaTheme.textSecondary)
                        .accessibilityLabel("Go back to previous onboarding step")
                    }
                    Text("Step \(min(app.onboardingStep + 1, 4)) of 4")
                        .font(.caption.bold())
                        .foregroundStyle(MockexaTheme.primary)
                    Spacer()
                }
                
                ProgressView(value: Double(app.onboardingStep + 1), total: 4)
                    .tint(MockexaTheme.primary)
                
                if app.onboardingStep < 2 {
                    choiceStep(app.onboardingStep)
                } else if app.onboardingStep == 2 {
                    companyStep
                } else {
                    confidenceStep
                }
                
                Spacer()
                
                PrimaryButton(title: app.onboardingStep == 3 ? "Finish" : "Continue", icon: "arrow.right") {
                    if app.onboardingStep < 3 {
                        withAnimation(.spring) { app.onboardingStep += 1 }
                    } else {
                        let study = selections[0] ?? savedStudyField
                        let role = selections[1] ?? savedTargetRole
                        let companyList = companies.sorted().joined(separator: ", ")
                        let confidenceLevel = Int(confidence)
                        savedStudyField = study
                        savedTargetRole = role
                        savedTargetCompanies = companyList
                        savedConfidenceLevel = confidenceLevel
                        auth.saveOnboardingPreferences(
                            study: study,
                            role: role,
                            companies: companyList,
                            confidence: confidenceLevel
                        )
                        auth.setOnboardingCompleted(for: auth.currentUserId, completed: true)
                        app.enterApp()
                    }
                }
                .disabled(app.onboardingStep < 2 && selections[app.onboardingStep] == nil)
            }
            .padding(24)
            .foregroundStyle(MockexaTheme.darkNavy)
        }
    }
    
    @ViewBuilder func choiceStep(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(steps[index].0)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)
            ForEach(steps[index].1, id: \.self) { item in
                SelectableRow(title: item, selected: selections[index] == item) {
                    selections[index] = item
                }
            }
        }
    }
    
    var companyStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where do you want to work?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)
            Text("Choose as many as you like.")
                .font(.subheadline)
                .foregroundStyle(MockexaTheme.textSecondary)
            ScrollView {
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                    ForEach(CompanyInfo.all.map(\.name), id: \.self) { item in
                        SelectableRow(title: item, selected: companies.contains(item)) {
                            if companies.contains(item) {
                                companies.remove(item)
                            } else {
                                companies.insert(item)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 430)
        }
    }
    
    var confidenceStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("How confident do you feel about placements?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(MockexaTheme.darkNavy)
            GlassCard {
                VStack(spacing: 20) {
                    Text(["😰", "😐", "🙂", "🔥"][Int(confidence)])
                        .font(.system(size: 68))
                    Text(["Not confident", "Getting there", "Pretty confident", "Very confident"][Int(confidence)])
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MockexaTheme.darkNavy)
                    Slider(value: $confidence, in: 0...3, step: 1)
                        .tint(MockexaTheme.primary)
                }
            }
        }
    }
}

struct SelectableRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? MockexaTheme.primary : MockexaTheme.darkNavy)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selected ? MockexaTheme.primary : MockexaTheme.border)
            }
            .padding(18)
            .background(
                selected ? MockexaTheme.primary.opacity(0.08) : MockexaTheme.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? MockexaTheme.primary : MockexaTheme.border, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 4, y: 2)
        }
        .buttonStyle(PressButtonStyle())
    }
}
