/// Users Module
/// User profiles, reputation, and identity management
module event_platform::users;

use std::option::{Self, Option};
use std::string::String;
use sui::event;
use sui::object::{Self, UID, ID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EProfileAlreadyExists: u64 = 2;
const EInvalidReputation: u64 = 3;
const EInvalidRating: u64 = 4;

// === Constants ===
const MAX_REPUTATION_SCORE: u64 = 1000;
const MAX_RATING: u64 = 5;

// === One-Time-Witness ===
public struct USERS has drop {}

// === Main Structs ===

/// User profile (one per user)
public struct UserProfile has key {
    id: UID,
    owner: address,
    identity: UserIdentity,
    reputation: ReputationData,
    stats: UserStats,
    preferences: UserPreferences,
    created_at: u64,
}

/// Nested identity
public struct UserIdentity has drop, store {
    display_name: Option<String>,
    zklogin_sub: Option<String>,
    email_hash: Option<vector<u8>>,
    social_links: vector<String>,
}

/// Nested reputation
public struct ReputationData has drop, store {
    score: u64,
    organizer_rating: u64,
    attendee_rating: u64,
    badges: vector<ID>,
}

/// Nested stats (copyable)
public struct UserStats has copy, drop, store {
    events_created: u64,
    events_attended: u64,
    no_show_count: u64,
    tickets_transferred: u64,
    total_spent: u64,
}

/// Nested preferences
public struct UserPreferences has drop, store {
    notification_enabled: bool,
    favorite_categories: vector<String>,
    timezone: String,
}

/// Achievement badge
public struct AchievementBadge has key, store {
    id: UID,
    user: address,
    badge_type: String,
    earned_at: u64,
    metadata_url: String,
}

// === Event Logs ===

public struct ProfileCreated has copy, drop {
    profile_id: ID,
    owner: address,
    timestamp: u64,
}

public struct ProfileUpdated has copy, drop {
    profile_id: ID,
    timestamp: u64,
}

public struct ReputationUpdated has copy, drop {
    user: address,
    old_score: u64,
    new_score: u64,
    timestamp: u64,
}

public struct BadgeEarned has copy, drop {
    badge_id: ID,
    user: address,
    badge_type: String,
    timestamp: u64,
}

// === Public Functions ===

/// Create user profile
public fun create_profile(
    display_name: Option<String>,
    zklogin_sub: Option<String>,
    ctx: &mut TxContext,
): UserProfile {
    let owner = tx_context::sender(ctx);
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    let identity = UserIdentity {
        display_name,
        zklogin_sub,
        email_hash: option::none(),
        social_links: std::vector::empty(),
    };

    let reputation = ReputationData {
        score: 100, // Starting reputation
        organizer_rating: 0,
        attendee_rating: 0,
        badges: std::vector::empty(),
    };

    let stats = UserStats {
        events_created: 0,
        events_attended: 0,
        no_show_count: 0,
        tickets_transferred: 0,
        total_spent: 0,
    };

    let preferences = UserPreferences {
        notification_enabled: true,
        favorite_categories: std::vector::empty(),
        timezone: std::string::utf8(b"UTC"),
    };

    let profile_uid = object::new(ctx);
    let profile_id = object::uid_to_inner(&profile_uid);

    let profile = UserProfile {
        id: profile_uid,
        owner,
        identity,
        reputation,
        stats,
        preferences,
        created_at: current_time,
    };

    event::emit(ProfileCreated {
        profile_id,
        owner,
        timestamp: current_time,
    });

    profile
}

/// Update profile identity
public fun update_profile(profile: &mut UserProfile, new_identity: UserIdentity, ctx: &TxContext) {
    // Verify ownership
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    profile.identity = new_identity;

    event::emit(ProfileUpdated {
        profile_id: object::id(profile),
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Update profile preferences
public fun update_preferences(
    profile: &mut UserProfile,
    new_preferences: UserPreferences,
    ctx: &TxContext,
) {
    // Verify ownership
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    profile.preferences = new_preferences;

    event::emit(ProfileUpdated {
        profile_id: object::id(profile),
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Update reputation score
public(package) fun update_reputation(
    profile: &mut UserProfile,
    score_delta: u64,
    is_positive: bool,
    ctx: &TxContext,
) {
    let old_score = profile.reputation.score;

    if (is_positive) {
        let new_score = old_score + score_delta;
        if (new_score > MAX_REPUTATION_SCORE) {
            profile.reputation.score = MAX_REPUTATION_SCORE;
        } else {
            profile.reputation.score = new_score;
        };
    } else {
        if (score_delta > old_score) {
            profile.reputation.score = 0;
        } else {
            profile.reputation.score = old_score - score_delta;
        };
    };

    event::emit(ReputationUpdated {
        user: profile.owner,
        old_score,
        new_score: profile.reputation.score,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Update organizer rating
public(package) fun update_organizer_rating(profile: &mut UserProfile, rating: u64) {
    assert!(rating <= MAX_RATING, EInvalidRating);
    // Average with existing rating
    if (profile.reputation.organizer_rating == 0) {
        profile.reputation.organizer_rating = rating;
    } else {
        profile.reputation.organizer_rating = (profile.reputation.organizer_rating + rating) / 2;
    };
}

/// Update attendee rating
public(package) fun update_attendee_rating(profile: &mut UserProfile, rating: u64) {
    assert!(rating <= MAX_RATING, EInvalidRating);
    // Average with existing rating
    if (profile.reputation.attendee_rating == 0) {
        profile.reputation.attendee_rating = rating;
    } else {
        profile.reputation.attendee_rating = (profile.reputation.attendee_rating + rating) / 2;
    };
}

/// Increment events attended
public(package) fun increment_events_attended(profile: &mut UserProfile) {
    profile.stats.events_attended = profile.stats.events_attended + 1;
}

/// Increment events created
public(package) fun increment_events_created(profile: &mut UserProfile) {
    profile.stats.events_created = profile.stats.events_created + 1;
}

/// Record no-show
public(package) fun record_no_show(profile: &mut UserProfile, ctx: &TxContext) {
    profile.stats.no_show_count = profile.stats.no_show_count + 1;

    // Penalty: reduce reputation
    let penalty = 10;
    update_reputation(profile, penalty, false, ctx);
}

/// Record ticket transfer
public(package) fun record_ticket_transfer(profile: &mut UserProfile) {
    profile.stats.tickets_transferred = profile.stats.tickets_transferred + 1;
}

/// Add to total spent
public(package) fun add_total_spent(profile: &mut UserProfile, amount: u64) {
    profile.stats.total_spent = profile.stats.total_spent + amount;
}

/// Mint achievement badge
public fun mint_achievement_badge(
    profile: &mut UserProfile,
    badge_type: String,
    metadata_url: String,
    ctx: &mut TxContext,
): AchievementBadge {
    let badge_uid = object::new(ctx);
    let badge_id = object::uid_to_inner(&badge_uid);
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    let badge = AchievementBadge {
        id: badge_uid,
        user: profile.owner,
        badge_type,
        earned_at: current_time,
        metadata_url,
    };

    // Add badge ID to profile
    std::vector::push_back(&mut profile.reputation.badges, badge_id);

    event::emit(BadgeEarned {
        badge_id,
        user: profile.owner,
        badge_type: badge.badge_type,
        timestamp: current_time,
    });

    badge
}

/// Add social link
public fun add_social_link(profile: &mut UserProfile, link: String, ctx: &TxContext) {
    // Verify ownership
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    std::vector::push_back(&mut profile.identity.social_links, link);
}

/// Add favorite category
public fun add_favorite_category(profile: &mut UserProfile, category: String, ctx: &TxContext) {
    // Verify ownership
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    std::vector::push_back(&mut profile.preferences.favorite_categories, category);
}

/// Set email hash
public fun set_email_hash(profile: &mut UserProfile, email_hash: vector<u8>, ctx: &TxContext) {
    // Verify ownership
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    profile.identity.email_hash = option::some(email_hash);
}

// === View Functions ===

/// Get reputation score
public fun get_reputation_score(profile: &UserProfile): u64 {
    profile.reputation.score
}

/// Get user stats
public fun get_user_stats(profile: &UserProfile): (u64, u64, u64, u64, u64) {
    (
        profile.stats.events_created,
        profile.stats.events_attended,
        profile.stats.no_show_count,
        profile.stats.tickets_transferred,
        profile.stats.total_spent,
    )
}

/// Get reputation data
public fun get_reputation_data(profile: &UserProfile): (u64, u64, u64, u64) {
    (
        profile.reputation.score,
        profile.reputation.organizer_rating,
        profile.reputation.attendee_rating,
        std::vector::length(&profile.reputation.badges),
    )
}

/// Get display name
public fun get_display_name(profile: &UserProfile): Option<String> {
    profile.identity.display_name
}

/// Get zklogin sub
public fun get_zklogin_sub(profile: &UserProfile): Option<String> {
    profile.identity.zklogin_sub
}

/// Get profile owner
public fun get_owner(profile: &UserProfile): address {
    profile.owner
}

/// Get created timestamp
public fun get_created_at(profile: &UserProfile): u64 {
    profile.created_at
}

/// Get notification preference
public fun is_notification_enabled(profile: &UserProfile): bool {
    profile.preferences.notification_enabled
}

/// Get timezone
public fun get_timezone(profile: &UserProfile): String {
    profile.preferences.timezone
}

/// Get favorite categories
public fun get_favorite_categories(profile: &UserProfile): &vector<String> {
    &profile.preferences.favorite_categories
}

/// Get badge info
public fun get_badge_info(badge: &AchievementBadge): (address, String, u64, String) {
    (badge.user, badge.badge_type, badge.earned_at, badge.metadata_url)
}

/// Get all badge IDs from profile
public fun get_badge_ids(profile: &UserProfile): &vector<ID> {
    &profile.reputation.badges
}

/// Check if user has any no-shows
public fun has_no_shows(profile: &UserProfile): bool {
    profile.stats.no_show_count > 0
}

/// Create identity struct
public fun create_identity(
    display_name: Option<String>,
    zklogin_sub: Option<String>,
    email_hash: Option<vector<u8>>,
    social_links: vector<String>,
): UserIdentity {
    UserIdentity {
        display_name,
        zklogin_sub,
        email_hash,
        social_links,
    }
}

/// Create preferences struct
public fun create_preferences(
    notification_enabled: bool,
    favorite_categories: vector<String>,
    timezone: String,
): UserPreferences {
    UserPreferences {
        notification_enabled,
        favorite_categories,
        timezone,
    }
}

// === Test Functions ===
#[test_only]
public fun create_test_profile(owner: address, ctx: &mut TxContext): UserProfile {
    let identity = UserIdentity {
        display_name: option::some(std::string::utf8(b"Test User")),
        zklogin_sub: option::none(),
        email_hash: option::none(),
        social_links: std::vector::empty(),
    };

    let reputation = ReputationData {
        score: 100,
        organizer_rating: 0,
        attendee_rating: 0,
        badges: std::vector::empty(),
    };

    let stats = UserStats {
        events_created: 0,
        events_attended: 0,
        no_show_count: 0,
        tickets_transferred: 0,
        total_spent: 0,
    };

    let preferences = UserPreferences {
        notification_enabled: true,
        favorite_categories: std::vector::empty(),
        timezone: std::string::utf8(b"UTC"),
    };

    UserProfile {
        id: object::new(ctx),
        owner,
        identity,
        reputation,
        stats,
        preferences,
        created_at: tx_context::epoch_timestamp_ms(ctx),
    }
}
