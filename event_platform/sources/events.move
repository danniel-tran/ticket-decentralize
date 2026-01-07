/// Events Module
/// Core event entity and lifecycle management
module event_platform::events;

use std::string::String;
use sui::event;
use sui::table::{Self, Table};
use event_platform::access_control::{Self, EventOrganizerCap};
use event_platform::users::{Self, UserProfile, BadgeRegistry};
use event_platform::payments::{Self, EventTreasury};

// ======== Error Codes ========
const ENotAuthorized: u64 = 3000;
const EInvalidTime: u64 = 3001;
const EInvalidStatus: u64 = 3002;
const EEventFull: u64 = 3003;
const ERegistrationClosed: u64 = 3004;
const EEventAlreadyStarted: u64 = 3005;
const EAlreadyRegistered: u64 = 3007;
const ENotRegistered: u64 = 3008;
const EAlreadyCheckedIn: u64 = 3009;
const EInvalidCapacity: u64 = 3010;

// ======== Status Constants ========
const STATUS_DRAFT: u8 = 0;
const STATUS_OPEN: u8 = 1;
const STATUS_IN_PROGRESS: u8 = 2;
const STATUS_COMPLETED: u8 = 3;
const STATUS_CANCELLED: u8 = 4;

// ======== Structs ========

/// Main event object (SHARED)
public struct Event has key {
    id: UID,
    organizer: address,
    metadata: EventMetadata,
    config: EventConfig,
    stats: EventStats,
    status: u8,
    attendees: Table<address, AttendeeInfo>,
    created_at: u64,
    updated_at: u64,
}

public struct EventMetadata has store, drop {
    title: String,
    description: String,
    walrus_blob_id: String,
    image_url: String,
    category: String,
    tags: vector<String>,
}

public struct EventConfig has store, drop {
    start_time: u64,
    end_time: u64,
    registration_deadline: u64,
    capacity: u64,
    ticket_price: u64,
    requires_approval: bool,
    is_transferable: bool,
    refund_deadline: u64,
}

public struct EventStats has copy, drop, store {
    registered: u64,
    attended: u64,
    revenue: u64,
    refunded: u64,
}

public struct AttendeeInfo has store, drop {
    registered_at: u64,
    checked_in: bool,
    check_in_time: Option<u64>,
}

/// Event registry for discovery (SHARED)
public struct EventRegistry has key {
    id: UID,
    total_events: u64,
    platform_fee_percent: u64,
    events_by_category: Table<String, vector<ID>>,
}

// ======== Events ========

public struct EventCreated has copy, drop {
    event_id: ID,
    organizer: address,
    title: String,
    category: String,
    timestamp: u64,
}

public struct EventPublished has copy, drop {
    event_id: ID,
    timestamp: u64,
}

public struct EventUpdated has copy, drop {
    event_id: ID,
    timestamp: u64,
}

public struct EventCancelled has copy, drop {
    event_id: ID,
    reason: String,
    timestamp: u64,
}

public struct EventStarted has copy, drop {
    event_id: ID,
    timestamp: u64,
}

public struct EventCompleted has copy, drop {
    event_id: ID,
    total_attended: u64,
    timestamp: u64,
}

public struct AttendeeRegistered has copy, drop {
    event_id: ID,
    attendee: address,
    timestamp: u64,
}

public struct AttendeeCheckedIn has copy, drop {
    event_id: ID,
    attendee: address,
    timestamp: u64,
}

// ======== Init Function ========

fun init(ctx: &mut TxContext) {
    let registry = EventRegistry {
        id: object::new(ctx),
        total_events: 0,
        platform_fee_percent: 250,  // 2.5% fixed
        events_by_category: table::new(ctx),
    };
    transfer::share_object(registry);
}

// ======== Public Functions ========

/// Create a new event
public fun create_event(
    registry: &mut EventRegistry,
    user_profile: &mut UserProfile,
    badge_registry: &mut BadgeRegistry,
    metadata: EventMetadata,
    config: EventConfig,
    ctx: &mut TxContext,
): (EventOrganizerCap, EventTreasury) {
    let sender = tx_context::sender(ctx);

    // Validate profile owner
    assert!(users::get_owner(user_profile) == sender, ENotAuthorized);

    // Validate times
    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(config.start_time > now, EInvalidTime);
    assert!(config.end_time > config.start_time, EInvalidTime);
    assert!(config.registration_deadline <= config.start_time, EInvalidTime);
    assert!(config.refund_deadline <= config.start_time, EInvalidTime);
    assert!(config.capacity > 0, EInvalidCapacity);

    // Create Event object
    let event_id = object::new(ctx);
    let event_id_value = object::uid_to_inner(&event_id);

    let event = Event {
        id: event_id,
        organizer: sender,
        metadata,
        config,
        stats: EventStats {
            registered: 0,
            attended: 0,
            revenue: 0,
            refunded: 0,
        },
        status: STATUS_DRAFT,
        attendees: table::new(ctx),
        created_at: now,
        updated_at: now,
    };

    // Share Event object
    let category = event.metadata.category;
    let title = event.metadata.title;

    event::emit(EventCreated {
        event_id: event_id_value,
        organizer: sender,
        title,
        category,
        timestamp: now,
    });

    // Add to category index
    if (!table::contains(&registry.events_by_category, category)) {
        table::add(&mut registry.events_by_category, category, vector::empty());
    };
    let category_events = table::borrow_mut(&mut registry.events_by_category, category);
    vector::push_back(category_events, event_id_value);

    registry.total_events = registry.total_events + 1;

    transfer::share_object(event);

    // Update UserProfile stats
    users::increment_events_created(user_profile, badge_registry, ctx);

    // Create EventTreasury
    let treasury = payments::create_event_treasury(event_id_value, sender, ctx);

    // Grant EventOrganizerCap
    let cap = access_control::create_organizer_cap(event_id_value, ctx);

    (cap, treasury)
}

/// Publish event (change from DRAFT to OPEN)
public fun publish_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    ctx: &TxContext,
) {
    let event_id = object::id(event);
    access_control::verify_organizer(cap, event_id, ctx);

    assert!(event.status == STATUS_DRAFT, EInvalidStatus);

    event.status = STATUS_OPEN;
    event.updated_at = tx_context::epoch_timestamp_ms(ctx);

    event::emit(EventPublished {
        event_id,
        timestamp: event.updated_at,
    });
}

/// Update event metadata
public fun update_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    new_metadata: EventMetadata,
    ctx: &TxContext,
) {
    let event_id = object::id(event);
    access_control::verify_can_update(cap, event_id, ctx);

    event.metadata = new_metadata;
    event.updated_at = tx_context::epoch_timestamp_ms(ctx);

    event::emit(EventUpdated {
        event_id,
        timestamp: event.updated_at,
    });
}

/// Cancel event
public fun cancel_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    reason: String,
    user_profile: &mut UserProfile,
    ctx: &TxContext,
) {
    let event_id = object::id(event);
    access_control::verify_can_cancel(cap, event_id, ctx);

    // Can only cancel before event starts
    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(now < event.config.start_time, EEventAlreadyStarted);

    event.status = STATUS_CANCELLED;
    event.updated_at = now;

    event::emit(EventCancelled {
        event_id,
        reason,
        timestamp: now,
    });

    // Apply penalty to organizer
    users::apply_cancellation_penalty(user_profile, ctx);
}

/// Start event (manual or automatic)
public fun start_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    ctx: &TxContext,
) {
    let event_id = object::id(event);
    access_control::verify_organizer(cap, event_id, ctx);

    assert!(event.status == STATUS_OPEN, EInvalidStatus);

    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(now >= event.config.start_time, EInvalidTime);

    event.status = STATUS_IN_PROGRESS;
    event.updated_at = now;

    event::emit(EventStarted {
        event_id,
        timestamp: now,
    });
}

/// Complete event
public fun complete_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    ctx: &TxContext,
) {
    let event_id = object::id(event);
    access_control::verify_organizer(cap, event_id, ctx);

    assert!(event.status == STATUS_IN_PROGRESS, EInvalidStatus);

    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(now >= event.config.end_time, EInvalidTime);

    event.status = STATUS_COMPLETED;
    event.updated_at = now;

    event::emit(EventCompleted {
        event_id,
        total_attended: event.stats.attended,
        timestamp: now,
    });
}

// ======== Package Functions ========

/// Register attendee (called by tickets module)
public(package) fun register_attendee(
    event: &mut Event,
    attendee: address,
    ctx: &TxContext,
) {
    assert!(event.status == STATUS_OPEN, ERegistrationClosed);
    assert!(event.stats.registered < event.config.capacity, EEventFull);
    assert!(!table::contains(&event.attendees, attendee), EAlreadyRegistered);

    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(now <= event.config.registration_deadline, ERegistrationClosed);

    let attendee_info = AttendeeInfo {
        registered_at: now,
        checked_in: false,
        check_in_time: option::none(),
    };

    table::add(&mut event.attendees, attendee, attendee_info);
    event.stats.registered = event.stats.registered + 1;
    event.updated_at = now;

    event::emit(AttendeeRegistered {
        event_id: object::id(event),
        attendee,
        timestamp: now,
    });
}

/// Unregister attendee (for refunds)
public(package) fun unregister_attendee(event: &mut Event, attendee: address) {
    assert!(table::contains(&event.attendees, attendee), ENotRegistered);

    let attendee_info = table::remove(&mut event.attendees, attendee);

    // Only allow unregister if not checked in
    assert!(!attendee_info.checked_in, EAlreadyCheckedIn);

    event.stats.registered = event.stats.registered - 1;
}

/// Check in attendee
public(package) fun check_in_attendee(
    event: &mut Event,
    attendee: address,
    ctx: &TxContext,
) {
    assert!(table::contains(&event.attendees, attendee), ENotRegistered);

    let attendee_info = table::borrow_mut(&mut event.attendees, attendee);
    assert!(!attendee_info.checked_in, EAlreadyCheckedIn);

    let now = tx_context::epoch_timestamp_ms(ctx);
    attendee_info.checked_in = true;
    attendee_info.check_in_time = option::some(now);

    event.stats.attended = event.stats.attended + 1;
    event.updated_at = now;

    event::emit(AttendeeCheckedIn {
        event_id: object::id(event),
        attendee,
        timestamp: now,
    });
}

/// Add revenue to stats
public(package) fun add_revenue(event: &mut Event, amount: u64) {
    event.stats.revenue = event.stats.revenue + amount;
}

/// Add refunded amount to stats
public(package) fun add_refunded(event: &mut Event, amount: u64) {
    event.stats.refunded = event.stats.refunded + amount;
}

/// Transfer attendee registration (for ticket transfers)
public(package) fun transfer_attendee_registration(
    event: &mut Event,
    from: address,
    to: address,
) {
    assert!(table::contains(&event.attendees, from), ENotRegistered);
    assert!(!table::contains(&event.attendees, to), EAlreadyRegistered);

    let attendee_info = table::remove(&mut event.attendees, from);
    table::add(&mut event.attendees, to, attendee_info);
}

// ======== View Functions ========

public fun get_status(event: &Event): u8 {
    event.status
}

public fun is_open(event: &Event): bool {
    event.status == STATUS_OPEN
}

public fun is_full(event: &Event): bool {
    event.stats.registered >= event.config.capacity
}

public fun can_register(event: &Event, ctx: &TxContext): bool {
    let now = tx_context::epoch_timestamp_ms(ctx);
    event.status == STATUS_OPEN &&
    event.stats.registered < event.config.capacity &&
    now <= event.config.registration_deadline
}

public fun get_ticket_price(event: &Event): u64 {
    event.config.ticket_price
}

public fun is_transferable(event: &Event): bool {
    event.config.is_transferable
}

public fun can_refund(event: &Event, ctx: &TxContext): bool {
    let now = tx_context::epoch_timestamp_ms(ctx);
    event.status == STATUS_OPEN &&
    now <= event.config.refund_deadline
}

public fun is_attendee_registered(event: &Event, attendee: address): bool {
    table::contains(&event.attendees, attendee)
}

public fun is_attendee_checked_in(event: &Event, attendee: address): bool {
    if (table::contains(&event.attendees, attendee)) {
        let attendee_info = table::borrow(&event.attendees, attendee);
        attendee_info.checked_in
    } else {
        false
    }
}

public fun get_organizer(event: &Event): address {
    event.organizer
}

public fun get_capacity(event: &Event): u64 {
    event.config.capacity
}

public fun get_registered_count(event: &Event): u64 {
    event.stats.registered
}

public fun get_attended_count(event: &Event): u64 {
    event.stats.attended
}

public fun get_start_time(event: &Event): u64 {
    event.config.start_time
}

public fun get_end_time(event: &Event): u64 {
    event.config.end_time
}

public fun get_title(event: &Event): String {
    event.metadata.title
}

public fun get_category(event: &Event): String {
    event.metadata.category
}

public fun get_platform_fee_percent(registry: &EventRegistry): u64 {
    registry.platform_fee_percent
}

public fun get_total_events(registry: &EventRegistry): u64 {
    registry.total_events
}
