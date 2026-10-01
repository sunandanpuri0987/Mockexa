from app.controllers.gd_friends import FriendsGDMatchmaker, FriendsGDRoomStore, RewardWalletStore
import time


def test_private_friends_room_requires_three_and_awards_points():
    wallets = RewardWalletStore()
    rooms = FriendsGDRoomStore(wallets)
    room = rooms.create("u1", "Aarav", "Should internships always be paid?", "balanced", 10, 8)
    rooms.join(room.code, "u2", "Diya")

    try:
        rooms.start(room, "u1")
        assert False, "two people must not start a private room"
    except ValueError:
        pass

    rooms.join(room.code, "u3", "Kabir")
    rooms.set_ready(room, "u2", True)
    rooms.set_ready(room, "u3", True)
    rooms.start(room, "u1")
    entry = rooms.contribute(
        room, "u2",
        "Internships should be paid because evidence shows unpaid roles reduce access. I recommend a measured policy safeguard.",
    )

    assert room.status == "live"
    assert entry["score"] > 40
    assert wallets.snapshot("u2")["coins"] > 0


def test_online_matchmaking_starts_at_four_and_fills_to_six():
    wallets = RewardWalletStore()
    rooms = FriendsGDRoomStore(wallets)
    matcher = FriendsGDMatchmaker(rooms)

    for index in range(1, 4):
        result = matcher.enqueue(f"u{index}", f"User {index}", "balanced", 10)
        assert result["state"] == "waiting"
        assert result["players_found"] == index

    fourth = matcher.enqueue("u4", "User 4", "balanced", 10)
    assert fourth["state"] == "matched"
    assert fourth["room"]["status"] == "live"
    assert fourth["room"]["minimum_participants"] == 4
    assert fourth["room"]["max_participants"] == 6

    fifth = matcher.enqueue("u5", "User 5", "balanced", 10)
    sixth = matcher.enqueue("u6", "User 6", "balanced", 10)
    assert fifth["room"]["room_id"] == fourth["room"]["room_id"]
    assert sixth["players_found"] == 6
    assert len(sixth["room"]["participants"]) == 6

    seventh = matcher.enqueue("u7", "User 7", "balanced", 10)
    assert seventh["state"] == "waiting"
    assert seventh["players_found"] == 1


def test_live_room_completes_at_timer_and_rejects_late_contribution():
    wallets = RewardWalletStore()
    rooms = FriendsGDRoomStore(wallets)
    room = rooms.create("u1", "Aarav", "Should internships always be paid?", "balanced", 5, 6)
    rooms.join(room.code, "u2", "Diya")
    rooms.join(room.code, "u3", "Kabir")
    rooms.set_ready(room, "u2", True)
    rooms.set_ready(room, "u3", True)
    rooms.start(room, "u1")
    room.started_at = time.time() - 301

    snapshot = rooms.snapshot(room, "u1")

    assert snapshot["status"] == "completed"
    assert snapshot["remaining_seconds"] == 0
    try:
        rooms.contribute(room, "u1", "This contribution is too late.")
        assert False, "expired rooms must reject new contributions"
    except RuntimeError:
        pass


def test_redeemed_boost_is_consumed_and_has_real_effect():
    wallets = RewardWalletStore()
    wallets.grant("speaker", xp=0, coins=100, event_id="seed")
    wallets.redeem("speaker", "power_boost")
    result = wallets.grant("speaker", xp=20, coins=5, event_id="practice:one")
    assert result["xp"] == 40
    assert result["coins"] == 20  # 100 - 90 cost + doubled 5
    assert result["inventory"]["power_boost"] == 0


def test_leaderboard_orders_by_xp_and_masks_names():
    wallets = RewardWalletStore()
    wallets.set_display_name("u1", "Aarav Sharma")
    wallets.set_display_name("u2", "Diya Mehta")
    wallets.grant("u1", xp=120, coins=15, event_id="one")
    wallets.grant("u2", xp=280, coins=20, event_id="two")

    board = wallets.leaderboard("u1")

    assert [row["display_name"] for row in board["entries"]] == ["Diya M.", "Aarav S."]
    assert board["entries"][1]["is_current_user"] is True
    assert board["current_user_rank"] == 2
    assert board["total_players"] == 2


def test_leaderboard_endpoint_includes_authenticated_user(client, auth_headers):
    response = client.get("/gd/rewards/leaderboard", headers=auth_headers)
    assert response.status_code == 200
    payload = response.json()
    assert payload["current_user_rank"] == 1
    assert payload["total_players"] == 1
    assert payload["entries"][0]["is_current_user"] is True
