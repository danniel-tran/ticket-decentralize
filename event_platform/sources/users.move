/// Users Module
/// User identity, reputation, and achievement system
module event_platform::users;

use std::string::String;
use sui::event;
use sui::table::{Self, Table};

// ======== Error Codes ========
const ENotAuthorized: u64 = 2000;
const EInvalidRating: u64 = 2001;
const EProfileNotFound: u64 = 2002;

// ======== Reputation Constants ========
const STARTING_REPUTATION: u64 = 500;
const MAX_REPUTATION: u64 = 1000;
const MIN_REPUTATION: u64 = 0;

const REPUTATION_EVENT_CREATED: u64 = 10;
const REPUTATION_EVENT_ATTENDED: u64 = 5;
const REPUTATION_NO_SHOW_PENALTY: u64 = 10;
const REPUTATION_CANCELLED_PENALTY: u64 = 20;

const MAX_RATING: u64 = 100;

// ======== Badge Rarity ========
const RARITY_COMMON: u8 = 0;
const RARITY_RARE: u8 = 1;
const RARITY_EPIC: u8 = 2;
const RARITY_LEGENDARY: u8 = 3;

// ======== Milestone Constants ========
const MILESTONE_FIRST_TIMER: u64 = 1;
const MILESTONE_ENTHUSIAST: u64 = 10;
const MILESTONE_LEGEND: u64 = 50;
const MILESTONE_CENTURY: u64 = 100;

const MILESTONE_RISING_ORGANIZER: u64 = 5;
const MILESTONE_VETERAN_ORGANIZER: u64 = 25;

// ======== Structs ========

public struct UserProfile has key {
    id: UID,
    owner: address,
    identity: UserIdentity,
    reputation: ReputationData,
    stats: UserStats,
    preferences: UserPreferences,
    created_at: u64,
    updated_at: u64,
}

public struct UserIdentity has store, drop {
    display_name: Option<String>,
    zklogin_sub: Option<String>,
    zklogin_provider: Option<String>,
    email_hash: Option<vector<u8>>,
    avatar_url: Option<String>,
    bio: Option<String>,
    social_links: vector<String>,
}

public struct ReputationData has store, drop {
    score: u64,
    organizer_rating: u64,
    attendee_rating: u64,
    organizer_rating_count: u64,
    attendee_rating_count: u64,
    verified_organizer: bool,
    badges: vector<ID>,
}

public struct UserStats has copy, drop, store {
    events_created: u64,
    events_attended: u64,
    no_show_count: u64,
    tickets_purchased: u64,
    tickets_transferred: u64,
    total_spent: u64,
}

public struct UserPreferences has store, drop {
    notification_enabled: bool,
    favorite_categories: vector<String>,
    timezone: String,
    language: String,
}

/// Achievement badge NFT
public struct AchievementBadge has key, store {
    id: UID,
    user: address,
    badge_type: String,
    name: String,
    description: String,
    metadata_url: String,
    earned_at: u64,
    rarity: u8,
}

/// Badge registry for tracking all badges
public struct BadgeRegistry has key {
    id: UID,
    total_badges: u64,
    badges_by_user: Table<address, vector<ID>>,
}

// ======== Events ========

public struct ProfileCreated has copy, drop {
    profile_id: ID,
    owner: address,
    timestamp: u64,
}

public struct ProfileUpdated has copy, drop {
    profile_id: ID,
    owner: address,
    timestamp: u64,
}

public struct ReputationUpdated has copy, drop {
    profile_id: ID,
    owner: address,
    old_score: u64,
    new_score: u64,
    timestamp: u64,
}

public struct BadgeEarned has copy, drop {
    badge_id: ID,
    user: address,
    badge_type: String,
    name: String,
    rarity: u8,
    timestamp: u64,
}

// ======== Init Function ========

fun init(ctx: &mut TxContext) {
    let registry = BadgeRegistry {
        id: object::new(ctx),
        total_badges: 0,
        badges_by_user: table::new(ctx),
    };
    transfer::share_object(registry);
}

// ======== Public Functions ========

/// Create basic user profile
public fun create_profile(
    display_name: Option<String>,
    zklogin_sub: Option<String>,
    ctx: &mut TxContext,
): UserProfile {
    let profile_id = object::new(ctx);
    let owner = tx_context::sender(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ProfileCreated {
        profile_id: object::uid_to_inner(&profile_id),
        owner,
        timestamp,
    });

    UserProfile {
        id: profile_id,
        owner,
        identity: UserIdentity {
            display_name,
            zklogin_sub,
            zklogin_provider: option::none(),
            email_hash: option::none(),
            avatar_url: option::none(),
            bio: option::none(),
            social_links: vector::empty(),
        },
        reputation: ReputationData {
            score: STARTING_REPUTATION,
            organizer_rating: 0,
            attendee_rating: 0,
            organizer_rating_count: 0,
            attendee_rating_count: 0,
            verified_organizer: false,
            badges: vector::empty(),
        },
        stats: UserStats {
            events_created: 0,
            events_attended: 0,
            no_show_count: 0,
            tickets_purchased: 0,
            tickets_transferred: 0,
            total_spent: 0,
        },
        preferences: default_preferences(),
        created_at: timestamp,
        updated_at: timestamp,
    }
}

/// Create profile with zkLogin
public fun create_profile_with_zklogin(
    display_name: String,
    zklogin_sub: String,
    zklogin_provider: String,
    ctx: &mut TxContext,
): UserProfile {
    let profile_id = object::new(ctx);
    let owner = tx_context::sender(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ProfileCreated {
        profile_id: object::uid_to_inner(&profile_id),
        owner,
        timestamp,
    });

    UserProfile {
        id: profile_id,
        owner,
        identity: UserIdentity {
            display_name: option::some(display_name),
            zklogin_sub: option::some(zklogin_sub),
            zklogin_provider: option::some(zklogin_provider),
            email_hash: option::none(),
            avatar_url: option::none(),
            bio: option::none(),
            social_links: vector::empty(),
        },
        reputation: ReputationData {
            score: STARTING_REPUTATION,
            organizer_rating: 0,
            attendee_rating: 0,
            organizer_rating_count: 0,
            attendee_rating_count: 0,
            verified_organizer: false,
            badges: vector::empty(),
        },
        stats: UserStats {
            events_created: 0,
            events_attended: 0,
            no_show_count: 0,
            tickets_purchased: 0,
            tickets_transferred: 0,
            total_spent: 0,
        },
        preferences: default_preferences(),
        created_at: timestamp,
        updated_at: timestamp,
    }
}

/// Update user identity
public fun update_identity(
    profile: &mut UserProfile,
    new_identity: UserIdentity,
    ctx: &TxContext,
) {
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    profile.identity = new_identity;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ProfileUpdated {
        profile_id: object::id(profile),
        owner: profile.owner,
        timestamp: profile.updated_at,
    });
}

/// Update user preferences
public fun update_preferences(
    profile: &mut UserProfile,
    new_preferences: UserPreferences,
    ctx: &TxContext,
) {
    assert!(profile.owner == tx_context::sender(ctx), ENotAuthorized);

    profile.preferences = new_preferences;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ProfileUpdated {
        profile_id: object::id(profile),
        owner: profile.owner,
        timestamp: profile.updated_at,
    });
}

// ======== Package Functions (Called by other modules) ========

/// Increment events created and update reputation
public(package) fun increment_events_created(
    profile: &mut UserProfile,
    badge_registry: &mut BadgeRegistry,
    ctx: &mut TxContext,
) {
    profile.stats.events_created = profile.stats.events_created + 1;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    // Update reputation
    update_reputation(profile, REPUTATION_EVENT_CREATED, true, ctx);

    // Check for organizer milestones
    check_organizer_milestones(profile, badge_registry, ctx);
}

/// Increment events attended and update reputation
public(package) fun increment_events_attended(
    profile: &mut UserProfile,
    badge_registry: &mut BadgeRegistry,
    ctx: &mut TxContext,
) {
    profile.stats.events_attended = profile.stats.events_attended + 1;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    // Update reputation
    update_reputation(profile, REPUTATION_EVENT_ATTENDED, true, ctx);

    // Check for attendance milestones
    check_attendance_milestones(profile, badge_registry, ctx);
}

/// Record no-show and apply penalty
public(package) fun record_no_show(profile: &mut UserProfile, ctx: &TxContext) {
    profile.stats.no_show_count = profile.stats.no_show_count + 1;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    // Apply penalty
    update_reputation(profile, REPUTATION_NO_SHOW_PENALTY, false, ctx);
}

/// Increment tickets purchased
public(package) fun increment_tickets_purchased(profile: &mut UserProfile) {
    profile.stats.tickets_purchased = profile.stats.tickets_purchased + 1;
}

/// Increment tickets transferred
public(package) fun increment_tickets_transferred(profile: &mut UserProfile) {
    profile.stats.tickets_transferred = profile.stats.tickets_transferred + 1;
}

/// Add to total spent
public(package) fun add_total_spent(profile: &mut UserProfile, amount: u64) {
    profile.stats.total_spent = profile.stats.total_spent + amount;
}

/// Update reputation score
public(package) fun update_reputation(
    profile: &mut UserProfile,
    score_delta: u64,
    is_positive: bool,
    ctx: &TxContext,
) {
    let old_score = profile.reputation.score;
    let new_score;

    if (is_positive) {
        new_score = if (old_score + score_delta > MAX_REPUTATION) {
            MAX_REPUTATION
        } else {
            old_score + score_delta
        };
    } else {
        new_score = if (old_score < score_delta) {
            MIN_REPUTATION
        } else {
            old_score - score_delta
        };
    };

    profile.reputation.score = new_score;
    profile.updated_at = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ReputationUpdated {
        profile_id: object::id(profile),
        owner: profile.owner,
        old_score,
        new_score,
        timestamp: profile.updated_at,
    });
}

/// Update organizer rating (weighted average)
public(package) fun update_organizer_rating(profile: &mut UserProfile, rating: u64) {
    assert!(rating <= MAX_RATING, EInvalidRating);

    let count = profile.reputation.organizer_rating_count;
    let old_rating = profile.reputation.organizer_rating;

    // Calculate weighted average
    let new_rating = if (count == 0) {
        rating
    } else {
        ((old_rating * count) + rating) / (count + 1)
    };

    profile.reputation.organizer_rating = new_rating;
    profile.reputation.organizer_rating_count = count + 1;

    // Verify organizer status if rating is high enough
    if (new_rating >= 80 && count >= 5) {
        profile.reputation.verified_organizer = true;
    };
}

/// Update attendee rating (weighted average)
public(package) fun update_attendee_rating(profile: &mut UserProfile, rating: u64) {
    assert!(rating <= MAX_RATING, EInvalidRating);

    let count = profile.reputation.attendee_rating_count;
    let old_rating = profile.reputation.attendee_rating;

    // Calculate weighted average
    let new_rating = if (count == 0) {
        rating
    } else {
        ((old_rating * count) + rating) / (count + 1)
    };

    profile.reputation.attendee_rating = new_rating;
    profile.reputation.attendee_rating_count = count + 1;
}

/// Apply event cancellation penalty
public(package) fun apply_cancellation_penalty(profile: &mut UserProfile, ctx: &TxContext) {
    update_reputation(profile, REPUTATION_CANCELLED_PENALTY, false, ctx);
}

// ======== Badge Functions ========

/// Check attendance milestones and award badges
fun check_attendance_milestones(
    profile: &mut UserProfile,
    registry: &mut BadgeRegistry,
    ctx: &mut TxContext,
) {
    let attended = profile.stats.events_attended;

    if (attended == MILESTONE_FIRST_TIMER) {
        mint_badge(
            profile,
            registry,
            b"first_timer",
            b"First Timer",
            b"Attended your first event!",
            RARITY_COMMON,
            ctx,
        );
    } else if (attended == MILESTONE_ENTHUSIAST) {
        mint_badge(
            profile,
            registry,
            b"event_enthusiast",
            b"Event Enthusiast",
            b"Attended 10 events!",
            RARITY_RARE,
            ctx,
        );
    } else if (attended == MILESTONE_LEGEND) {
        mint_badge(
            profile,
            registry,
            b"event_legend",
            b"Event Legend",
            b"Attended 50 events!",
            RARITY_EPIC,
            ctx,
        );
    } else if (attended == MILESTONE_CENTURY) {
        mint_badge(
            profile,
            registry,
            b"century_club",
            b"Century Club",
            b"Attended 100 events!",
            RARITY_LEGENDARY,
            ctx,
        );
    };
}

/// Check organizer milestones and award badges
fun check_organizer_milestones(
    profile: &mut UserProfile,
    registry: &mut BadgeRegistry,
    ctx: &mut TxContext,
) {
    let created = profile.stats.events_created;

    if (created == MILESTONE_RISING_ORGANIZER) {
        mint_badge(
            profile,
            registry,
            b"rising_organizer",
            b"Rising Organizer",
            b"Created 5 events!",
            RARITY_RARE,
            ctx,
        );
    } else if (created == MILESTONE_VETERAN_ORGANIZER) {
        mint_badge(
            profile,
            registry,
            b"veteran_organizer",
            b"Veteran Organizer",
            b"Created 25 events!",
            RARITY_EPIC,
            ctx,
        );
    };
}

/// Mint achievement badge
fun mint_badge(
    profile: &mut UserProfile,
    registry: &mut BadgeRegistry,
    badge_type: vector<u8>,
    name: vector<u8>,
    description: vector<u8>,
    rarity: u8,
    ctx: &mut TxContext,
) {
    let badge_id = object::new(ctx);
    let user = profile.owner;
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    let badge_type_str = std::string::utf8(badge_type);
    let name_str = std::string::utf8(name);

    event::emit(BadgeEarned {
        badge_id: object::uid_to_inner(&badge_id),
        user,
        badge_type: badge_type_str,
        name: name_str,
        rarity,
        timestamp,
    });

    let badge = AchievementBadge {
        id: badge_id,
        user,
        badge_type: badge_type_str,
        name: name_str,
        description: std::string::utf8(description),
        metadata_url: std::string::utf8(b""),  // To be updated with Walrus URL
        earned_at: timestamp,
        rarity,
    };

    let badge_id = object::id(&badge);

    // Add to profile
    vector::push_back(&mut profile.reputation.badges, badge_id);

    // Track in registry
    if (!table::contains(&registry.badges_by_user, user)) {
        table::add(&mut registry.badges_by_user, user, vector::empty());
    };
    let user_badges = table::borrow_mut(&mut registry.badges_by_user, user);
    vector::push_back(user_badges, badge_id);

    registry.total_badges = registry.total_badges + 1;

    // Transfer to user
    transfer::public_transfer(badge, user);
}

// ======== Helper Functions ========

fun default_preferences(): UserPreferences {
    UserPreferences {
        notification_enabled: true,
        favorite_categories: vector::empty(),
        timezone: std::string::utf8(b"UTC"),
        language: std::string::utf8(b"en"),
    }
}

// ======== Getter Functions ========

public fun get_owner(profile: &UserProfile): address {
    profile.owner
}

public fun get_reputation_score(profile: &UserProfile): u64 {
    profile.reputation.score
}

public fun get_organizer_rating(profile: &UserProfile): u64 {
    profile.reputation.organizer_rating
}

public fun get_attendee_rating(profile: &UserProfile): u64 {
    profile.reputation.attendee_rating
}

public fun is_verified_organizer(profile: &UserProfile): bool {
    profile.reputation.verified_organizer
}

public fun get_events_created(profile: &UserProfile): u64 {
    profile.stats.events_created
}

public fun get_events_attended(profile: &UserProfile): u64 {
    profile.stats.events_attended
}

public fun get_total_spent(profile: &UserProfile): u64 {
    profile.stats.total_spent
}

public fun get_display_name(profile: &UserProfile): &Option<String> {
    &profile.identity.display_name
}
