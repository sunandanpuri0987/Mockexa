import SwiftUI

enum FriendsGDIntent: String {
    case create, join, matchmaking
}

@MainActor
final class FriendsGDViewModel: ObservableObject {
    @Published var room: FriendsGDRoomResponse?
    @Published var wallet: RewardWalletResponse?
    @Published var queueState = "idle"
    @Published var playersFound = 0
    @Published var isLoading = false
    @Published var isContributing = false
    @Published var errorMessage: String?

    private let api = APIClient.shared

    func enter(intent: FriendsGDIntent, topic: String, duration: Int, mode: String, code: String, token: String) async {
        guard room == nil, queueState == "idle", !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            switch intent {
            case .create:
                room = try await api.post(
                    endpoint: "/gd/friends/rooms",
                    body: FriendsGDCreateRequest(topic: topic, durationMinutes: duration, mode: mode, maxParticipants: 8),
                    token: token
                )
            case .join:
                room = try await api.post(endpoint: "/gd/friends/join", body: FriendsGDJoinRequest(roomCode: code), token: token)
            case .matchmaking:
                let result: FriendsGDMatchmakingResponse = try await api.post(
                    endpoint: "/gd/friends/matchmaking",
                    body: FriendsGDMatchmakeRequest(mode: mode, durationMinutes: duration), token: token
                )
                apply(match: result)
            }
            await loadWallet(token: token)
        } catch { errorMessage = error.localizedDescription }
    }

    func poll(intent: FriendsGDIntent, token: String) async {
        while !Task.isCancelled {
            do {
                if intent == .matchmaking && room == nil {
                    let result: FriendsGDMatchmakingResponse = try await api.get(endpoint: "/gd/friends/matchmaking/status", token: token)
                    apply(match: result)
                } else if let roomId = room?.roomId {
                    let latest: FriendsGDRoomResponse = try await api.get(endpoint: "/gd/friends/rooms/\(roomId)", token: token)
                    room = latest
                }
            } catch is CancellationError { return }
            catch { errorMessage = error.localizedDescription }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    func toggleReady(token: String) async {
        guard let current = room, let me = current.participants.first(where: { $0.userId == current.viewerUserId }) else { return }
        do {
            room = try await api.post(endpoint: "/gd/friends/rooms/\(current.roomId)/ready", body: FriendsGDReadyRequest(ready: !me.ready), token: token)
        } catch { errorMessage = error.localizedDescription }
    }

    func start(token: String) async {
        guard let roomId = room?.roomId else { return }
        do { room = try await api.postEmpty(endpoint: "/gd/friends/rooms/\(roomId)/start", token: token) }
        catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func contribute(_ text: String, token: String) async -> Bool {
        guard let roomId = room?.roomId, !isContributing else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 3 else { return false }
        isContributing = true
        errorMessage = nil
        defer { isContributing = false }
        do {
            let result: FriendsGDContributionResponse = try await api.post(
                endpoint: "/gd/friends/rooms/\(roomId)/contributions",
                body: FriendsGDContributionRequest(text: clean), token: token
            )
            room = result.room; wallet = result.wallet
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func finish(token: String) async {
        guard let roomId = room?.roomId else { return }
        do {
            let result: FriendsGDFinishResponse = try await api.postEmpty(endpoint: "/gd/friends/rooms/\(roomId)/finish", token: token)
            room = result.room; wallet = result.wallet
        } catch { errorMessage = error.localizedDescription }
    }

    func cancelMatchmaking(token: String) async {
        do {
            let _: FriendsGDMatchmakingResponse = try await api.delete(endpoint: "/gd/friends/matchmaking", token: token)
            queueState = "idle"
        } catch { errorMessage = error.localizedDescription }
    }

    func loadWallet(token: String) async {
        wallet = try? await api.get(endpoint: "/gd/rewards/wallet", token: token)
    }

    private func apply(match: FriendsGDMatchmakingResponse) {
        queueState = match.state; playersFound = match.playersFound ?? 0
        if let matchedRoom = match.room { room = matchedRoom; Haptics.success() }
    }
}

struct FriendsGDRoomView: View {
    let intent: FriendsGDIntent
    let topic: String
    let durationStr: String
    let mode: String
    let roomCode: String
    @StateObject private var vm = FriendsGDViewModel()
    @StateObject private var voice = VoiceFoundation.shared
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @FocusState private var messageFocused: Bool

    private var duration: Int { Int(durationStr.filter(\.isNumber)) ?? 10 }
    private var isHost: Bool { vm.room?.viewerUserId == vm.room?.hostUserId }

    var body: some View {
        ZStack {
            AppBackground()
            ScrollView {
                VStack(spacing: 16) {
                    if let error = vm.errorMessage {
                        Text(error).font(.caption).foregroundStyle(MockexaTheme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let room = vm.room {
                        roomHeader(room)
                        leaderboard(room)
                        if room.status == "lobby" { lobby(room) }
                        else { liveRoom(room) }
                    } else { matchmakingCard }
                }.padding(20)
            }
        }
        .navigationTitle(intent == .matchmaking ? "Online GD" : "Friends GD")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let token = auth.accessToken, !token.isEmpty else { vm.errorMessage = "Please log in first."; return }
            await vm.enter(intent: intent, topic: topic, duration: duration, mode: mode, code: roomCode, token: token)
            await vm.poll(intent: intent, token: token)
        }
        .onAppear {
            voice.onSilenceDetected = { finalText in
                guard let token = auth.accessToken else { return }
                let captured = voice.stopListeningAndProcess()
                Task { await vm.contribute(captured.isEmpty ? finalText : captured, token: token) }
            }
        }
        .onDisappear {
            voice.stopListening()
            voice.onSilenceDetected = nil
        }
    }

    private var matchmakingCard: some View {
        GlassCard {
            VStack(spacing: 18) {
                ProgressView().scaleEffect(1.3).tint(MockexaTheme.primary)
                Text("Finding your group…").font(.title3.bold())
                Text("\(vm.playersFound)/4 ready • Starts automatically at 4 • Room stays open up to 6")
                    .font(.subheadline).foregroundStyle(MockexaTheme.textSecondary).multilineTextAlignment(.center)
                Text("A random topic will be revealed after matching.").font(.caption).foregroundStyle(MockexaTheme.primary)
                Button("Cancel Matchmaking") {
                    guard let token = auth.accessToken else { return }
                    Task { await vm.cancelMatchmaking(token: token); dismiss() }
                }.foregroundStyle(MockexaTheme.destructive)
            }.frame(maxWidth: .infinity).padding(.vertical, 28)
        }
    }

    private func roomHeader(_ room: FriendsGDRoomResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(room.status.uppercased(), systemImage: room.status == "live" ? "dot.radiowaves.left.and.right" : "person.3.fill")
                        .font(.caption.bold()).foregroundStyle(MockexaTheme.primary)
                    Spacer()
                    if intent != .matchmaking {
                        Button { UIPasteboard.general.string = room.roomCode; Haptics.success() } label: {
                            Label(room.roomCode, systemImage: "doc.on.doc.fill").font(.system(.subheadline, design: .monospaced).bold())
                        }
                    }
                }
                Text(room.topic).font(.title3.bold()).foregroundStyle(MockexaTheme.darkNavy)
                HStack {
                    Label("\(room.participants.count)/\(room.maxParticipants)", systemImage: "person.2.fill")
                    Label(
                        String(format: "%02d:%02d", max(0, room.remainingSeconds) / 60, max(0, room.remainingSeconds) % 60),
                        systemImage: "timer"
                    )
                    Spacer()
                    if let wallet = vm.wallet { Label("\(wallet.coins)", systemImage: "circle.hexagongrid.fill") }
                }.font(.caption.bold()).foregroundStyle(MockexaTheme.textSecondary)
            }
        }
    }

    private func leaderboard(_ room: FriendsGDRoomResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(room.status == "lobby" ? "PARTICIPANTS" : "LIVE LEADERBOARD").font(.caption.bold()).foregroundStyle(MockexaTheme.primary)
                ForEach(Array(room.participants.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.bold()).frame(width: 20)
                        AIAvatar(initials: String(member.name.prefix(1)).uppercased(), color: MockexaTheme.primary)
                            .scaleEffect(0.72).frame(width: 32, height: 32)
                        VStack(alignment: .leading) {
                            Text(member.name + (member.isHost ? " • Host" : "")).font(.subheadline.bold())
                            Text(member.ready ? "Ready" : "Not ready").font(.caption2).foregroundStyle(member.ready ? MockexaTheme.success : MockexaTheme.textSecondary)
                        }
                        Spacer()
                        if room.status != "lobby" { Text("\(member.points) pts").font(.subheadline.bold()).foregroundStyle(MockexaTheme.primary) }
                    }
                }
            }
        }
    }

    private func lobby(_ room: FriendsGDRoomResponse) -> some View {
        VStack(spacing: 12) {
            Text("Minimum \(room.minimumParticipants) participants required. Share the code with friends.")
                .font(.subheadline).foregroundStyle(MockexaTheme.textSecondary).multilineTextAlignment(.center)
            if !isHost {
                Button("Toggle Ready") { guard let token = auth.accessToken else { return }; Task { await vm.toggleReady(token: token) } }
                    .buttonStyle(.borderedProminent).tint(MockexaTheme.primary)
            } else {
                Button("Start Discussion") { guard let token = auth.accessToken else { return }; Task { await vm.start(token: token) } }
                    .buttonStyle(.borderedProminent).tint(MockexaTheme.primary).disabled(!room.canStart)
                if !room.canStart { Text("Waiting for enough ready participants").font(.caption).foregroundStyle(MockexaTheme.textSecondary) }
            }
        }
    }

    private func liveRoom(_ room: FriendsGDRoomResponse) -> some View {
        VStack(spacing: 14) {
            if room.status == "live" && room.remainingSeconds <= 60 {
                GlassCard {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("CLOSING PHASE", systemImage: "flag.checkered")
                            .font(.caption.bold())
                            .foregroundStyle(MockexaTheme.warning)
                        Text("One member should conclude now: summarise common ground, the remaining trade-off, and the group's practical recommendation.")
                            .font(.subheadline)
                            .foregroundStyle(MockexaTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if room.transcript.isEmpty {
                GlassCard { Text("Start with a clear opening position. Evidence, reasoning, collaboration and solutions earn more points.")
                    .font(.subheadline).foregroundStyle(MockexaTheme.textSecondary) }
            } else {
                ForEach(room.transcript) { item in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack { Text(item.speaker).font(.subheadline.bold()); Spacer(); Text("+\(item.score) pts  +\(item.coins) coins").font(.caption.bold()).foregroundStyle(MockexaTheme.primary) }
                            Text(item.text).font(.subheadline)
                            if !item.signals.isEmpty { Text(item.signals.map { $0.capitalized }.joined(separator: " • ")).font(.caption2).foregroundStyle(MockexaTheme.success) }
                        }
                    }
                }
            }
            if room.status == "live" {
                HStack(spacing: 10) {
                    TextField("Add your point…", text: $message, axis: .vertical).focused($messageFocused)
                        .padding(12).background(MockexaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        Task {
                            if voice.currentState == .listening { voice.stopListening() }
                            else if await voice.requestPermissions() { try? voice.startListening() }
                        }
                    } label: { Image(systemName: voice.currentState == .listening ? "stop.fill" : "mic.fill") }
                        .buttonStyle(.bordered).tint(MockexaTheme.primary)
                    Button { submit() } label: { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.borderedProminent).tint(MockexaTheme.primary)
                        .disabled(message.trimmingCharacters(in: .whitespaces).count < 3 || vm.isContributing)
                }
                if voice.currentState == .listening { Text(voice.recognizedText.isEmpty ? "Listening…" : voice.recognizedText).font(.caption).foregroundStyle(MockexaTheme.primary) }
                if isHost {
                    Button("End & Award Rankings") { guard let token = auth.accessToken else { return }; Task { await vm.finish(token: token) } }
                        .foregroundStyle(MockexaTheme.destructive).padding(.top, 8)
                }
            } else {
                Text("Discussion complete • Ranking bonuses awarded").font(.headline).foregroundStyle(MockexaTheme.success)
            }
        }
    }

    private func submit() {
        guard let token = auth.accessToken else { return }
        let text = message
        messageFocused = false
        Task {
            if await vm.contribute(text, token: token) {
                message = ""
            }
        }
    }
}

@MainActor
final class RewardsViewModel: ObservableObject {
    @Published var wallet: RewardWalletResponse?
    @Published var error: String?
    func load(token: String) async { do { wallet = try await APIClient.shared.get(endpoint: "/gd/rewards/wallet", token: token) } catch { self.error = error.localizedDescription } }
    func redeem(_ id: String, token: String) async {
        do { wallet = try await APIClient.shared.post(endpoint: "/gd/rewards/redeem", body: RewardRedeemRequest(rewardId: id), token: token); Haptics.success() }
        catch { self.error = error.localizedDescription }
    }
}

struct RewardsCenterView: View {
    @EnvironmentObject private var auth: AuthManager
    @StateObject private var vm = RewardsViewModel()
    var body: some View {
        ScreenContainer {
            VStack(alignment: .leading, spacing: 18) {
                Text("Rewards Center").font(.largeTitle.bold()).padding(.top, 8)
                if let wallet = vm.wallet {
                    GlassCard {
                        HStack { rewardStat("Level", "\(wallet.level)", "star.fill"); rewardStat("XP", "\(wallet.xp)", "bolt.fill"); rewardStat("Coins", "\(wallet.coins)", "circle.hexagongrid.fill") }
                    }
                    Text("Use rewards across GD, Technical, HR and Company practice.").font(.subheadline).foregroundStyle(MockexaTheme.textSecondary)
                    ForEach(wallet.catalog) { reward in
                        GlassCard {
                            HStack(spacing: 14) {
                                Image(systemName: reward.icon).font(.title2).foregroundStyle(MockexaTheme.primary).frame(width: 36)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(reward.title).font(.headline)
                                    Text(reward.description).font(.caption).foregroundStyle(MockexaTheme.textSecondary)
                                    if let owned = wallet.inventory[reward.id], owned > 0 { Text("Owned: \(owned)").font(.caption.bold()).foregroundStyle(MockexaTheme.success) }
                                }
                                Spacer()
                                Button("\(reward.cost)") { guard let token = auth.accessToken else { return }; Task { await vm.redeem(reward.id, token: token) } }
                                    .buttonStyle(.borderedProminent).tint(MockexaTheme.primary).disabled(wallet.coins < reward.cost)
                            }
                        }
                    }
                } else { ProgressView() }
                if let error = vm.error { Text(error).font(.caption).foregroundStyle(MockexaTheme.destructive) }
            }
        }.task { if let token = auth.accessToken { await vm.load(token: token) } }
    }
    private func rewardStat(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 5) { Image(systemName: icon).foregroundStyle(MockexaTheme.primary); Text(value).font(.title3.bold()); Text(label).font(.caption) }.frame(maxWidth: .infinity)
    }
}
