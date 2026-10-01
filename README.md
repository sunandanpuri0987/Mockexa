# Mockexa

> AI-powered interview preparation built for placement-ready candidates.

Mockexa is a native iOS application and FastAPI backend service engineered to help candidates prepare for placement interviews. It provides real-time, interactive practice sessions across **Technical Coding/System Design**, **HR Behavioral Interviews**, and **Group Discussion (GD) Panel Simulations**, complete with multi-dimensional scoring and actionable feedback.

The application combines a high-performance native SwiftUI interface—featuring touchscreen-native 3D gestures and custom micro-interactions—with a resilient backend architecture powered by FastAPI, Supabase Authentication, and Gemini LLM intelligence.

---

## ✨ Features

### 🔐 Authentication & Session Security
- **Email & Password**: Native signup and login via Supabase Auth REST API.
- **Google OAuth**: Integrated PKCE web authentication session (`ASWebAuthenticationSession`) with deep linking callback (`prepaai://auth/callback`).
- **Apple Sign In**: Native iOS `ASAuthorizationAppleIDProvider` credential request exchanged securely with Supabase Auth.
- **Phone OTP**: SMS verification code requests and session token verification.
- **Keychain Persistence**: Secure encrypted local token storage (`PREPAI_ACTIVE_SESSION`) for persistent sign-in.
- **Cross-Device Onboarding Sync**: Account-scoped onboarding completion state synced with Supabase `user_metadata` and isolated locally per user UUID.

### 🎯 Interview Practice Modes
- **Technical Interview**:
  - Select domain (Data Structures, Algorithms, System Design, Web Development, Databases) and difficulty level (1–5).
  - Code Editor mode with syntax monospaced formatting or Plain Text response editor.
  - Evaluation of correctness, completeness, relevance, and reasoning.
  - Automatic detection of missing concepts and misconceptions.
- **HR Behavioral Interview**:
  - STAR-method behavioral question prompts.
  - 7-dimension scoring: Clarity, Specificity, Ownership, Communication, Teamwork, Leadership, and Problem Solving.
  - Detailed, constructive interviewer feedback per response.
- **Group Discussion (GD) Panel**:
  - Multi-agent AI discussion panel simulation (Ananya, Rohan, Priya, Vikram).
  - Live conversation feed with speaker avatars, contribution input bar, and dynamic turn generation.
  - Group discussion quality metrics and comprehensive performance summary.

### 📊 Progress & Analytics
- **Placement Readiness Score**: Animated count-up score ring (0–100) reflecting overall candidate readiness.
- **Performance Trends**: Weekly progress trend line chart.
- **Mode Breakdown**: Side-by-side performance bars for GD, Technical, and HR tracks.
- **Practice History**: Interactive historical session catalog filterable by track, complete with detailed breakdown views and complete session transcripts.

### 👤 Personalization
- **Account-Aware Profiles**: Dynamic display name (`user_metadata.full_name`) and generated 2-letter avatar initials.
- **5-Step Onboarding Wizard**: Tailored configuration for field of study, college year, target role, preferred companies, and initial confidence rating.

---

## 🧠 How It Works

```
Candidate Launch
       │
       ▼
Session Check / Splash ───► (Unauthenticated) ───► Welcome / Get Started ───► Sign In / Sign Up
       │                                                                            │
       │ (Authenticated)                                                            │
       ▼                                                                            ▼
Check Account Onboarding Status ◄───────────────────────────────────────────────────┘
       │
       ├─────► Incomplete ───► 5-Step Onboarding Wizard ───► Sync to Supabase user_metadata
       │                                                             │
       └─────► Complete ─────────────────────────────────────────────┘
                               │
                               ▼
                    Main App Tab Dashboard
                               │
       ┌───────────────────────┼───────────────────────┐
       ▼                       ▼                       ▼
Technical Mode              HR Mode                 GD Mode
       │                       │                       │
       ▼                       ▼                       ▼
Code/Text Response     STAR Method Answer       Panel Contribution
       │                       │                       │
       └───────────────────────┼───────────────────────┘
                               │
                               ▼
                   Real-Time Evaluation / Report
                               │
                               ▼
                   Dashboard & History Analytics
```

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      iOS Application                        │
│                     (Native SwiftUI)                        │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
      AuthManager / Session            InterviewViewModels
  (Supabase REST / Keychain API)       (State & Transcript Engine)
               │                              │
               │                              ▼
               │                     APIClient (HTTP / REST)
               │                              │
               └──────────────┬───────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      FastAPI Backend                        │
│                (Uvicorn / Async Python)                     │
├─────────────────────────────────────────────────────────────┤
│  • /health                     • /technical/*               │
│  • /hr/*                       • /gd/*                      │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
               ▼                              ▼
       Supabase Database               Gemini LLM Engine
   (Session & User Storage)       (gemini-3.8-flash)
```

### Layer Responsibilities
1. **iOS Application (UI)**: Built with SwiftUI using modular components (`GlassCard`, `PrimaryButton`, `InteractiveTouchCard`). Handles route management (`AppRoute`), input interaction, and client-side view state.
2. **AuthManager**: Handles Supabase Auth REST endpoints, token rotation, Keychain security, OAuth deep links, and user-scoped local caching.
3. **InterviewViewModels**: Manages real-time interview state, question indices, user answer submissions, and backend REST communication.
4. **APIClient**: Provides asynchronous HTTP methods (`GET`, `POST`) with timeout handling, error mapping (`APIError`), and JSON payload serialization.
5. **FastAPI Backend**: Asynchronous Web API exposing endpoints for session initiation, turn processing, answer evaluation, and discussion management.
6. **AI & Repository Layer**: Integrates with Gemini LLM (`gemini-3.8-flash`) for response evaluation and logs session history to Supabase.

---

## 📱 iOS Application Details

### Main Components & Files
- **[`PrepAIApp.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/PrepAIApp.swift)**: Main application entry point initializing `@StateObject` singletons (`AppModel`, `AuthManager`).
- **[`RootAndOnboarding.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/RootAndOnboarding.swift)**: Core route controller (`AppRoute`), Splash reveal, `WelcomeView`, `AuthenticationView`, and 5-step `OnboardingView`.
- **[`AuthManager.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/AuthManager.swift)**: Manages Supabase Auth, Keychain access, OAuth flows, and account metadata.
- **[`MainScreens.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/MainScreens.swift)**: Contains `MainTabView`, `HomeView`, `PracticeHubView`, `DashboardView`, `HistoryView`, `SessionDetailView`, and `ProfileView`.
- **[`PracticeFlows.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/PracticeFlows.swift)**: Interactive screens for `PracticeSetupView`, `PanelView`, `LiveGDView`, `LiveInterviewView`, `SessionCompleteView`, `ReportView`, and `TranscriptView`.
- **[`DesignSystem.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/DesignSystem.swift)**: Theme tokens (`PrepTheme`), `GlassCard`, `PrimaryButton`, `ScoreRing`, `InteractiveTouchCard` (touchscreen 3D drag tilt), `HeroAmbientGlowView`, and `StaggeredEntranceModifier`.
- **[`InterviewViewModels.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/InterviewViewModels.swift)**: ViewModels (`TechnicalViewModel`, `HRViewModel`, `GDViewModel`) managing session lifecycles.
- **[`APIClient.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/APIClient.swift) & [`APISchemas.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/APISchemas.swift)**: Network request pipeline and strong DTO types.
- **[`Config.swift`](file:///Users/dhruvsoni/Desktop/PrepAI/UI/PrepAI/Config.swift)**: Environment configuration (`PrepConfig`) supporting dynamic backend host detection (`127.0.0.1:8000` for Simulator vs. LAN IP for physical device).

---

## 🔐 Authentication Implementation

- **Supabase Auth Integration**: Interacts directly with Supabase Auth REST endpoints (`/auth/v1/signup`, `/auth/v1/token?grant_type=password`, `/auth/v1/recover`, `/auth/v1/user`).
- **Keychain Storage**: Key-Value generic password item (`PREPAI_ACTIVE_SESSION`) for access tokens and refresh tokens.
- **Account Isolation**: Onboarding completion and display names are cached using account-isolated keys (`PREPAI_ONBOARDING_COMPLETED_<USER_ID>`, `PREPAI_USER_FULL_NAME_<USER_ID>`).
- **OAuth Deep Linking**: Handles custom URL scheme `prepaai://auth/callback` for Google Sign In PKCE exchange.

---

## ⚙️ Backend Implementation

### FastAPI Architecture (`Backend/app`)
- **Routers**:
  - `health.py`: Health check endpoint (`GET /health`).
  - `technical.py`: Endpoints `/technical/start`, `/technical/answer`, `/technical/finish/{session_id}`.
  - `hr.py`: Endpoints `/hr/start`, `/hr/answer`, `/hr/finish/{session_id}`.
  - `gd.py`: Endpoints `/gd/start`, `/gd/respond`, `/gd/finish/{session_id}`.
- **Controllers**:
  - `technical_controller.py`: Deterministic fallback question bank and rule-based evaluation.
  - `technical_gemini_backend.py`: Gemini LLM-backed evaluation pipeline.
  - `hr_controller.py` & `hr_gemini_backend.py`: HR interview evaluation pipeline.
  - `gd_controller.py`: Multi-agent GD discussion manager and performance evaluator.
- **Providers**:
  - `gemini_backend.py`: Wraps Gemini Python SDK for inference (`gemini-3.8-flash`).
  - `model_router.py`: Central routing layer for model selection and fallback handling.

---

## 📊 Current Product Status

| Module | Implementation Status | Notes |
|---|---|---|
| **Email/Password Auth** | ✅ Implemented & Verified | Supabase REST integration |
| **Google & Apple OAuth** | ✅ Implemented & Verified | Deep link & native credential handling |
| **Keychain & Session Persistence** | ✅ Implemented & Verified | Token encryption & auto-restoration |
| **Account-Scoped Onboarding Sync** | ✅ Implemented & Verified | Synced to Supabase `user_metadata` |
| **Home & Dashboard UI** | ✅ Implemented & Verified | Swift UI with touchscreen 3D gestures |
| **Technical Interview Engine** | ✅ Implemented & Verified | Curated + Gemini evaluation pipeline |
| **HR Behavioral Engine** | ✅ Implemented & Verified | STAR evaluation pipeline |
| **Group Discussion (GD) Engine** | ✅ Implemented & Verified | Multi-agent panel simulation |
| **History & Transcript View** | ✅ Implemented & Verified | Filterable session catalog |
| **FastAPI Backend Services** | ✅ Implemented & Verified | Async FastAPI on port 8000 |
| **Automated Test Suite** | ✅ Implemented & Verified | 24+ passing pytest backend tests |

---

## 🎨 UI / UX Design System

- **Color Palette**:
  - Primary Emerald: `#0F5A47`
  - Mint Accent: `#10B981`
  - Dark Navy (Headings): `#0F172A`
  - Slate (Secondary Text): `#64748B`
  - Soft Slate Border: `#E2E8F0`
  - App Background: `#F8FAFC` (Clean off-white with subtle mint radial studio glow)
  - Surface: `#FFFFFF` (Pure white card surfaces)
- **Touchscreen-Native 3D Interactions**:
  - `InteractiveTouchCard`: Uses zero-distance `DragGesture` to track real-time finger position on iOS touchscreens.
  - Dynamic 3D rotation (`5.0°` max tilt) towards finger location with spring physics (`.spring(response: 0.32, dampingFraction: 0.7)`).
  - Dynamic depth shadow tightening on press (`12pt` $\rightarrow$ `4pt`).
  - Icon scale (`1.06`) and arrow shift (`5pt` forward) micro-animations.
- **Staggered Entrance**: Smooth spring entrance animations (`StaggeredEntranceModifier`) staggered between `0.04s`–`0.42s`.
- **Hero Light Glow**: Continuous, subtle dual-layer emerald ambient blur (`HeroAmbientGlowView`).
- **Accessibility**: Full `@Environment(\.accessibilityReduceMotion)` support disabling 3D tilts and continuous animations when enabled.

---

## 📂 Project Structure

```
Mockexa/
├── UI/
│   ├── PrepAI/
│   │   ├── APIClient.swift
│   │   ├── APISchemas.swift
│   │   ├── AuthManager.swift
│   │   ├── Config.swift
│   │   ├── DesignSystem.swift
│   │   ├── Info.plist
│   │   ├── InterviewViewModels.swift
│   │   ├── MainScreens.swift
│   │   ├── Models.swift
│   │   ├── PracticeFlows.swift
│   │   ├── PrepAIApp.swift
│   │   └── RootAndOnboarding.swift
│   └── PrepAI.xcodeproj/
├── Backend/
│   ├── app/
│   │   ├── controllers/
│   │   │   ├── gd_controller.py
│   │   │   ├── hr_controller.py
│   │   │   ├── hr_gemini_backend.py
│   │   │   ├── technical_controller.py
│   │   │   └── technical_gemini_backend.py
│   │   ├── providers/
│   │   │   ├── gemini_backend.py
│   │   │   ├── llm_backend.py
│   │   │   └── model_router.py
│   │   ├── routers/
│   │   │   ├── gd.py
│   │   │   ├── health.py
│   │   │   ├── hr.py
│   │   │   └── technical.py
│   │   ├── schemas/
│   │   ├── auth.py
│   │   ├── config.py
│   │   ├── main.py
│   │   └── repository.py
│   ├── tests/
│   │   ├── test_api_technical_flow.py
│   │   ├── test_auth.py
│   │   ├── test_gd.py
│   │   ├── test_gemini_backend.py
│   │   ├── test_hr_flow.py
│   │   └── test_technical_controller.py
│   ├── .env.example
│   ├── requirements.txt
│   └── seed_questions_merged.sql
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites
- **macOS** 14.0+
- **Xcode** 15.0+ (iOS 17.0+ SDK)
- **Python** 3.10+

### 1. Running the FastAPI Backend

```bash
# Navigate to backend directory
cd Backend

# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env

# Run FastAPI development server
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Verify backend health at `http://127.0.0.1:8000/health` or open interactive docs at `http://127.0.0.1:8000/docs`.

### 2. Running the iOS Application

1. Open `UI/PrepAI.xcodeproj` in Xcode.
2. Select the `PrepAI` scheme and an iOS Simulator (e.g., iPhone 17 Pro Max).
3. Press `Cmd + R` to build and run.

To build via terminal:
```bash
xcodebuild -project UI/PrepAI.xcodeproj \
  -scheme PrepAI \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

---

## 🔧 Configuration

The application uses standard environment configuration files. Copy `Backend/.env.example` to `Backend/.env` and update the placeholders:

```env
GEMINI_API_KEY=YOUR_GEMINI_API_KEY
SUPABASE_URL=YOUR_SUPABASE_URL
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
SUPABASE_JWT_SECRET=YOUR_SUPABASE_JWT_SECRET
PREPAI_BACKEND_BASE_URL=http://127.0.0.1:8000
```

> **Security Note**: Never commit actual API keys or credentials to repository source control.

---

## 🧪 Testing

The backend test suite verifies authentication, controller logic, token budgets, and endpoint routers:

```bash
cd Backend
pytest tests/ -v
```

**Test Coverage Highlights**:
- Technical interview question progression and evaluation fallback routines.
- HR interview STAR evaluation and score computations.
- Group Discussion multi-agent turn management and lock synchronization.
- Supabase Auth JWT verification parsing.

---

## 📌 Known Limitations

1. **Physical Device Network Routing**: When running the iOS app on a physical iPhone, set `PrepConfig.baseURL` to your Mac's LAN IP address (e.g. `http://192.168.x.x:8000`) so the iPhone can reach the local FastAPI server.
2. **Gemini API Key**: Real-time LLM inference requires a valid `GEMINI_API_KEY` configured in `Backend/.env`. If unconfigured, the backend uses deterministic evaluation engines.

---

## 📄 License

License information will be added before public release.
