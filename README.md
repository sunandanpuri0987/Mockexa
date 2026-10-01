# Mockexa

> AI-powered interview preparation built for placement-ready candidates.

Mockexa is a native iOS application and FastAPI backend service engineered to help candidates prepare for placement interviews. It provides real-time, interactive practice sessions across **Technical Coding/System Design**, **HR Behavioral Interviews**, and **Group Discussion (GD) Panel Simulations**, complete with multi-dimensional scoring and actionable feedback.

The application combines a high-performance native SwiftUI interface—featuring touchscreen-native 3D gestures and custom micro-interactions—with a resilient backend architecture powered by FastAPI, Supabase Authentication, and Gemini LLM intelligence.

---

## ✨ Features

### 🔐 Authentication & Session Security
- **Email & Password**: Native signup and login via Supabase Auth REST API.
- **Google OAuth**: Integrated PKCE web authentication session (`ASWebAuthenticationSession`) with deep linking callback (`mockexa://auth/callback`).
- **Apple Sign In**: Native iOS `ASAuthorizationAppleIDProvider` credential request exchanged securely with Supabase Auth.
- **Phone OTP**: SMS verification code requests and session token verification.
- **Keychain Persistence**: Secure encrypted local token storage (`MOCKEXA_ACTIVE_SESSION`) for persistent sign-in.
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

### 🏢 Company Practice & Collaboration
- **Company Question Bank**: Searchable, source-backed question sets for major technology and consulting employers, with category filters and guided practice sessions.
- **Friends & Online GD**: Create or join rooms, use matchmaking, coordinate participant readiness, submit live contributions, and track rewards/leaderboards.
- **Session History APIs**: Authenticated summaries and detailed transcripts shared across practice modes.

### 📄 Resume & Voice Tools
- **Resume Workspace**: Build, import, validate, tailor, and preview resumes inside the iOS app.
- **Document Export**: Generate ATS-friendly PDF and DOCX resumes directly on-device.
- **Voice Practice**: Speech recognition and playback with ElevenLabs, OpenAI, and EdgeTTS backend fallbacks plus local iOS speech behavior.

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
│  • /health        • /technical/*      • /hr/*            │
│  • /gd/*          • /company/*        • /sessions/*      │
│  • /tts           • auth + persistence + model fallback     │
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
6. **AI, Speech & Repository Layer**: Integrates with Gemini for response evaluation, ElevenLabs/OpenAI/EdgeTTS for speech, and Supabase for authenticated session persistence. Deterministic fallbacks keep core interview practice available when external AI services are not configured.

---

## 📱 iOS Application Details

### Main Components & Files
- **[`MockexaApp.swift`](UI/Mockexa/MockexaApp.swift)**: Main application entry point initializing shared application and authentication state.
- **[`RootAndOnboarding.swift`](UI/Mockexa/RootAndOnboarding.swift)**: Core route controller, splash/welcome flow, authentication, and onboarding.
- **[`AuthManager.swift`](UI/Mockexa/AuthManager.swift)**: Supabase Auth, Keychain access, OAuth flows, token refresh, and account metadata.
- **[`MainScreens.swift`](UI/Mockexa/MainScreens.swift)**: Main tabs, home, practice hub, dashboard, history, session detail, and profile screens.
- **[`PracticeFlows.swift`](UI/Mockexa/PracticeFlows.swift)**: Technical, HR, and AI-panel GD setup, live sessions, reports, and transcripts.
- **[`CompanyQuestionBank.swift`](UI/Mockexa/CompanyQuestionBank.swift)**: Company catalog, sourced question browser, practice flow, and branded assets.
- **[`FriendsGD.swift`](UI/Mockexa/FriendsGD.swift)**: Friends-room and online-matchmaking GD experience.
- **[`ResumeViews.swift`](UI/Mockexa/ResumeViews.swift)**: Resume builder, analyzer, tailoring, preview, and export UI, supported by the resume model/service files.
- **[`VoiceFoundation.swift`](UI/Mockexa/VoiceFoundation.swift)**: Speech recognition, audio playback, silence detection, and voice orchestration.
- **[`DesignSystem.swift`](UI/Mockexa/DesignSystem.swift)**: Theme tokens and reusable interaction/animation components.
- **[`APIClient.swift`](UI/Mockexa/APIClient.swift) and [`APISchemas.swift`](UI/Mockexa/APISchemas.swift)**: Network request pipeline and strongly typed DTOs.
- **[`Config.swift`](UI/Mockexa/Config.swift)**: Backend and Supabase configuration. It defaults to loopback in the Simulator and the configured mDNS host on a physical device.

---

## 🔐 Authentication Implementation

- **Supabase Auth Integration**: Interacts directly with Supabase Auth REST endpoints (`/auth/v1/signup`, `/auth/v1/token?grant_type=password`, `/auth/v1/recover`, `/auth/v1/user`).
- **Keychain Storage**: Key-Value generic password item (`MOCKEXA_ACTIVE_SESSION`) for access tokens and refresh tokens.
- **Account Isolation**: Onboarding completion and display names are cached using account-isolated keys (`MOCKEXA_ONBOARDING_COMPLETED_<USER_ID>`, `MOCKEXA_USER_FULL_NAME_<USER_ID>`).
- **OAuth Deep Linking**: Handles custom URL scheme `mockexa://auth/callback` for Google Sign In PKCE exchange.

---

## ⚙️ Backend Implementation

### FastAPI Architecture (`Backend/app`)
- **Routers**:
  - `health.py`: Health check endpoint (`GET /health`).
  - `technical.py`: Endpoints `/technical/start`, `/technical/answer`, `/technical/finish/{session_id}`.
  - `hr.py`: Endpoints `/hr/start`, `/hr/answer`, `/hr/finish/{session_id}`.
  - `gd.py`: AI-panel GD endpoints plus friends rooms, online matchmaking, reward wallet, leaderboard, and redemption endpoints.
  - `company.py`: Company catalog, question browsing, and `/company/start`, `/company/answer`, `/company/finish/{session_id}`.
  - `sessions.py`: Authenticated session summaries (`GET /sessions`) and details (`GET /sessions/{session_id}`).
  - `tts.py`: Neural speech generation (`POST /tts`) with bounded in-memory caching.
- **Controllers**:
  - `technical_controller.py`: Deterministic fallback question bank and rule-based evaluation.
  - `technical_gemini_backend.py`: Gemini LLM-backed evaluation pipeline.
  - `hr_controller.py` and `hr_gemini_backend.py`: HR interview evaluation pipeline.
  - `gd_controller.py`: Multi-agent GD discussion manager and performance evaluator.
  - `gd_friends.py`: In-memory friends-room, matchmaking, and rewards service.
  - `company_controller.py`: Company-specific practice orchestration and scoring.
- **Providers**:
  - `gemini_backend.py`: Wraps the Gemini API for structured inference.
  - `model_router.py`: Central routing layer for model selection and fallback handling.
- **Persistence**:
  - `repository.py`: Supabase-backed session persistence with an in-memory fallback for local development and tests.

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
| **Friends & Online GD** | ✅ Implemented & Verified | Rooms, matchmaking, rewards, and leaderboard |
| **Company Question Practice** | ✅ Implemented & Verified | Catalog, sourced questions, scoring, and reports |
| **Resume Builder & Export** | ✅ Implemented & Verified | Import, edit, tailor, validate, PDF, and DOCX |
| **Voice & Neural TTS** | ✅ Implemented & Verified | iOS voice orchestration with ElevenLabs, OpenAI, and EdgeTTS providers |
| **History & Transcript View** | ✅ Implemented & Verified | Filterable session catalog |
| **FastAPI Backend Services** | ✅ Implemented & Verified | Async FastAPI on port 8000 |
| **Automated Test Suite** | ✅ Implemented & Verified | 150 passing backend tests |
| **iOS Simulator Build** | ✅ Implemented & Verified | Debug simulator build succeeds with code signing disabled |

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
├── Backend/
│   ├── app/
│   │   ├── controllers/       # Technical, HR, GD, friends GD, company practice
│   │   ├── data/              # Company question data
│   │   ├── providers/         # Gemini, model routing, GD generation
│   │   ├── routers/           # Health, interviews, sessions, company, TTS
│   │   ├── schemas/           # Pydantic request/response models
│   │   ├── utils/             # Session store and token budgets
│   │   ├── auth.py
│   │   ├── config.py
│   │   ├── main.py
│   │   └── repository.py
│   ├── tests/                 # 150 backend tests
│   ├── .env.example
│   ├── requirements.txt
│   └── seed_questions_merged.sql
├── UI/
│   ├── Mockexa/
│   │   ├── Assets.xcassets/
│   │   ├── APIClient.swift, APISchemas.swift
│   │   ├── AuthManager.swift, Config.swift
│   │   ├── MainScreens.swift, PracticeFlows.swift
│   │   ├── CompanyQuestionBank.swift, FriendsGD.swift
│   │   ├── ResumeModels.swift, ResumeService.swift, ResumeViewModel.swift
│   │   ├── ResumeViews.swift, PDFExportService.swift, DOCXExportService.swift
│   │   ├── VoiceFoundation.swift, LanguageValidator.swift
│   │   └── MockexaApp.swift, RootAndOnboarding.swift, DesignSystem.swift
│   └── Mockexa.xcodeproj/
├── MOCKEXA_CURRENT_PROJECT.md
├── PROJECT_OVERVIEW.md
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

1. Open `UI/Mockexa.xcodeproj` in Xcode.
2. Select the `Mockexa` scheme and an iOS Simulator (e.g., iPhone 17 Pro Max).
3. Press `Cmd + R` to build and run.

To build via terminal:
```bash
xcodebuild -project UI/Mockexa.xcodeproj \
  -scheme Mockexa \
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

# Optional neural text-to-speech
ELEVENLABS_API_KEY=YOUR_ELEVENLABS_API_KEY
OPENAI_API_KEY=YOUR_OPENAI_API_KEY
```

Gemini, ElevenLabs, and OpenAI are optional for local development: the backend uses deterministic interview evaluation and the TTS route can fall through to EdgeTTS when paid-provider credentials are unavailable. `USE_SUPABASE_PERSISTENCE=False` keeps session data in memory; set it to `True` only after configuring Supabase.

The iOS backend URL resolves in this order: a saved in-app override, the `MOCKEXA_BACKEND_BASE_URL` process environment variable, `Info.plist`, then the target-specific default. The Simulator defaults to `http://127.0.0.1:8000`; physical devices use the configured `.local` mDNS hostname.

> **Security Note**: Never commit actual API keys or credentials to repository source control.

---

## 🧪 Testing

The backend test suite verifies authentication, controller logic, token budgets, and endpoint routers:

```bash
Backend/.venv/bin/python -m pytest Backend/tests -q
```

**Test Coverage Highlights**:
- Technical interview question progression and evaluation fallback routines.
- HR interview STAR evaluation and score computations.
- Group Discussion multi-agent turn management and lock synchronization.
- Friends/online GD rooms, matchmaking, rewards, and input validation.
- Company question catalog and complete practice sessions.
- Session persistence/history and multi-provider TTS caching/error handling.
- Supabase Auth JWT verification parsing.

The current verified result is **150 passed**. The iOS target can be checked independently with the simulator `xcodebuild` command above.

---

## 📌 Known Limitations

1. **Physical Device Network Routing**: The iPhone and backend Mac must be reachable on the same network. If the default `.local` hostname does not resolve, set a backend URL override in the app or via `MOCKEXA_BACKEND_BASE_URL` using the Mac's LAN address.
2. **Gemini API Key**: Real-time LLM inference requires a valid `GEMINI_API_KEY` configured in `Backend/.env`. If unconfigured, the backend uses deterministic evaluation engines.
3. **Cloud Features**: Cross-device history, authenticated persistence, and friends matchmaking across processes depend on Supabase configuration. Paid neural voices require the corresponding ElevenLabs or OpenAI credentials; EdgeTTS remains the backend fallback.

---

## 📄 License

License information will be added before public release.
