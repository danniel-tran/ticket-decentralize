/// Events Module
/// Core event creation, registration, and lifecycle management
module event_platform::events;

use event_platform::access_control::{Self, EventOrganizerCap};
use std::string::String;
use sui::event;
use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EEventFull: u64 = 2;
const EInvalidTime: u64 = 3;
const EInvalidStatus: u64 = 4;
const EInvalidTransition: u64 = 5;
const ERegistrationClosed: u64 = 6;
const EEventAlreadyStarted: u64 = 7;

// === Constants ===
const STATUS_DRAFT: u8 = 0;
const STATUS_OPEN: u8 = 1;
const STATUS_IN_PROGRESS: u8 = 2;
const STATUS_COMPLETED: u8 = 3;
const STATUS_CANCELLED: u8 = 4;

const PLATFORM_FEE_PERCENT: u64 = 5; // 5% platform fee

// === One-Time-Witness ===
public struct EVENTS has drop {}

// === Main Structs ===

/// Shared registry (one per platform)
public struct EventRegistry has key {
    id: UID,
    total_events: u64,
    platform_fee_percent: u64,
    admin: address,
}

/// Main Event object (shared)
public struct Event has key, store {
    id: UID,
    organizer: address,
    metadata: EventMetadata,
    config: EventConfig,
    stats: EventStats,
    status: u8,
    attendees: Table<address, AttendeeInfo>,
}

/// Attendee information
public struct AttendeeInfo has drop, store {
    registered_at: u64,
    checked_in: bool,
    check_in_time: Option<u64>,
}

/// Nested metadata
public struct EventMetadata has drop, store {
    title: String,
    description: String,
    walrus_blob_id: String,
    image_url: String,
    tags: vector<String>,
}

/// Nested configuration
public struct EventConfig has drop, store {
    start_time: u64,
    end_time: u64,
    registration_deadline: u64,
    capacity: u64,
    ticket_price: u64,
    requires_approval: bool,
    is_transferable: bool,
    refund_deadline: u64,
}

/// Copyable event statistics
public struct EventStats has copy, drop, store {
    registered: u64,
    attended: u64,
    revenue: u64,
    refunded: u64,
}

// === Event Logs ===

public struct EventCreated has copy, drop {
    event_id: ID,
    organizer: address,
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

public struct EventStatusChanged has copy, drop {
    event_id: ID,
    old_status: u8,
    new_status: u8,
    timestamp: u64,
}

public struct RegistrationClosed has copy, drop {
    event_id: ID,
    final_count: u64,
    timestamp: u64,
}

// === Init Function ===

/// Initialize the module with a shared registry
fun init(_witness: EVENTS, ctx: &mut TxContext) {
    let registry = EventRegistry {
        id: object::new(ctx),
        total_events: 0,
        platform_fee_percent: PLATFORM_FEE_PERCENT,
        admin: tx_context::sender(ctx),
    };
    transfer::share_object(registry);
}

// === Public Functions ===

/// Create a new event in DRAFT status
public fun create_event(
    registry: &mut EventRegistry,
    metadata: EventMetadata,
    config: EventConfig,
    ctx: &mut TxContext,
): EventOrganizerCap {
    // Validate times
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    assert!(config.start_time > current_time, EInvalidTime);
    assert!(config.end_time > config.start_time, EInvalidTime);
    assert!(config.registration_deadline <= config.start_time, EInvalidTime);
    assert!(config.registration_deadline > current_time, EInvalidTime);
    assert!(config.refund_deadline <= config.start_time, EInvalidTime);

    // Create event stats
    let stats = EventStats {
        registered: 0,
        attended: 0,
        revenue: 0,
        refunded: 0,
    };

    // Create event object
    let event_uid = object::new(ctx);
    let event_id = object::uid_to_inner(&event_uid);

    let event_obj = Event {
        id: event_uid,
        organizer: tx_context::sender(ctx),
        metadata,
        config,
        stats,
        status: STATUS_DRAFT,
        attendees: table::new(ctx),
    };

    // Share the event object
    transfer::share_object(event_obj);

    // Update registry
    registry.total_events = registry.total_events + 1;

    // Emit event
    event::emit(EventCreated {
        event_id,
        organizer: tx_context::sender(ctx),
        timestamp: current_time,
    });

    // Grant organizer capability
    access_control::grant_organizer_cap(event_id, ctx)
}

/// Publish event (change status from DRAFT to OPEN)
public fun publish_event(event: &mut Event, cap: &EventOrganizerCap, ctx: &TxContext) {
    // Verify ownership
    assert!(access_control::verify_organizer(cap, object::id(event)), ENotAuthorized);

    // Verify current status is DRAFT
    assert!(event.status == STATUS_DRAFT, EInvalidTransition);

    // Verify registration deadline hasn't passed
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    assert!(current_time < event.config.registration_deadline, EInvalidTime);

    let old_status = event.status;
    event.status = STATUS_OPEN;

    event::emit(EventStatusChanged {
        event_id: object::id(event),
        old_status,
        new_status: STATUS_OPEN,
        timestamp: current_time,
    });

    event::emit(EventPublished {
        event_id: object::id(event),
        timestamp: current_time,
    });
}

/// Update event metadata (only if not started)
public fun update_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    new_metadata: EventMetadata,
    ctx: &TxContext,
) {
    // Verify ownership and permission
    assert!(access_control::verify_can_update(cap, object::id(event)), ENotAuthorized);

    // Cannot update if event has started
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    assert!(current_time < event.config.start_time, EEventAlreadyStarted);

    event.metadata = new_metadata;

    event::emit(EventUpdated {
        event_id: object::id(event),
        timestamp: current_time,
    });
}

/// Update event configuration (only if not started)
public fun update_event_config(
    event: &mut Event,
    cap: &EventOrganizerCap,
    new_config: EventConfig,
    ctx: &TxContext,
) {
    // Verify ownership and permission
    assert!(access_control::verify_can_update(cap, object::id(event)), ENotAuthorized);

    // Cannot update if event has started
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    assert!(current_time < event.config.start_time, EEventAlreadyStarted);

    // Validate new times
    assert!(new_config.start_time > current_time, EInvalidTime);
    assert!(new_config.end_time > new_config.start_time, EInvalidTime);
    assert!(new_config.registration_deadline <= new_config.start_time, EInvalidTime);

    event.config = new_config;

    event::emit(EventUpdated {
        event_id: object::id(event),
        timestamp: current_time,
    });
}

/// Cancel event
public fun cancel_event(
    event: &mut Event,
    cap: &EventOrganizerCap,
    reason: String,
    ctx: &TxContext,
) {
    // Verify ownership and permission
    assert!(access_control::verify_can_cancel(cap, object::id(event)), ENotAuthorized);

    // Cannot cancel if already completed
    assert!(event.status != STATUS_COMPLETED, EInvalidTransition);
    assert!(event.status != STATUS_CANCELLED, EInvalidTransition);

    let old_status = event.status;
    event.status = STATUS_CANCELLED;

    let current_time = tx_context::epoch_timestamp_ms(ctx);

    event::emit(EventStatusChanged {
        event_id: object::id(event),
        old_status,
        new_status: STATUS_CANCELLED,
        timestamp: current_time,
    });

    event::emit(EventCancelled {
        event_id: object::id(event),
        reason,
        timestamp: current_time,
    });
}

/// Close registration manually
public fun close_registration(event: &mut Event, cap: &EventOrganizerCap, ctx: &TxContext) {
    // Verify ownership
    assert!(access_control::verify_organizer(cap, object::id(event)), ENotAuthorized);

    // Must be OPEN to close
    assert!(event.status == STATUS_OPEN, EInvalidTransition);

    let old_status = event.status;
    event.status = STATUS_IN_PROGRESS;

    let current_time = tx_context::epoch_timestamp_ms(ctx);

    event::emit(EventStatusChanged {
        event_id: object::id(event),
        old_status,
        new_status: STATUS_IN_PROGRESS,
        timestamp: current_time,
    });

    event::emit(RegistrationClosed {
        event_id: object::id(event),
        final_count: event.stats.registered,
        timestamp: current_time,
    });
}

/// Mark event as completed
public fun complete_event(event: &mut Event, cap: &EventOrganizerCap, ctx: &TxContext) {
    // Verify ownership
    assert!(access_control::verify_organizer(cap, object::id(event)), ENotAuthorized);

    // Must be IN_PROGRESS
    assert!(event.status == STATUS_IN_PROGRESS, EInvalidTransition);

    // Event should have ended
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    assert!(current_time >= event.config.end_time, EInvalidTime);

    let old_status = event.status;
    event.status = STATUS_COMPLETED;

    event::emit(EventStatusChanged {
        event_id: object::id(event),
        old_status,
        new_status: STATUS_COMPLETED,
        timestamp: current_time,
    });
}

/// Register attendee (internal function for tickets module)
public(package) fun register_attendee(event: &mut Event, attendee: address, ctx: &TxContext) {
    // Check status
    assert!(event.status == STATUS_OPEN, ERegistrationClosed);

    // Check capacity
    assert!(event.stats.registered < event.config.capacity, EEventFull);

    // Check if already registered
    assert!(!table::contains(&event.attendees, attendee), ENotAuthorized);

    let current_time = tx_context::epoch_timestamp_ms(ctx);

    // Add attendee
    let attendee_info = AttendeeInfo {
        registered_at: current_time,
        checked_in: false,
        check_in_time: std::option::none(),
    };
    table::add(&mut event.attendees, attendee, attendee_info);

    // Update stats
    event.stats.registered = event.stats.registered + 1;
}

/// Mark attendee as checked in (internal function for tickets module)
public(package) fun check_in_attendee(event: &mut Event, attendee: address, ctx: &TxContext) {
    assert!(table::contains(&event.attendees, attendee), ENotAuthorized);

    let attendee_info = table::borrow_mut(&mut event.attendees, attendee);

    if (!attendee_info.checked_in) {
        attendee_info.checked_in = true;
        attendee_info.check_in_time = std::option::some(tx_context::epoch_timestamp_ms(ctx));
        event.stats.attended = event.stats.attended + 1;
    };
}

/// Unregister attendee (for refunds - internal function)
public(package) fun unregister_attendee(event: &mut Event, attendee: address) {
    if (table::contains(&event.attendees, attendee)) {
        table::remove(&mut event.attendees, attendee);
        if (event.stats.registered > 0) {
            event.stats.registered = event.stats.registered - 1;
        };
    };
}

/// Add revenue to event stats (internal function for payments module)
public(package) fun add_revenue(event: &mut Event, amount: u64) {
    event.stats.revenue = event.stats.revenue + amount;
}

/// Add refunded amount to stats (internal function for payments module)
public(package) fun add_refunded(event: &mut Event, amount: u64) {
    event.stats.refunded = event.stats.refunded + amount;
}

// === View Functions ===

/// Get event status
public fun get_event_status(event: &Event): u8 {
    event.status
}

/// Get event details
public fun get_event_info(event: &Event): (String, String, u64, u64, u64, u64, u8) {
    (
        event.metadata.title,
        event.metadata.description,
        event.config.start_time,
        event.config.end_time,
        event.config.capacity,
        event.stats.registered,
        event.status,
    )
}

/// Get event statistics
public fun get_event_stats(event: &Event): (u64, u64, u64, u64) {
    (event.stats.registered, event.stats.attended, event.stats.revenue, event.stats.refunded)
}

/// Get event configuration
public fun get_event_config(event: &Event): &EventConfig {
    &event.config
}

/// Get event metadata
public fun get_event_metadata(event: &Event): &EventMetadata {
    &event.metadata
}

/// Check if registration is open
public fun is_registration_open(event: &Event, ctx: &TxContext): bool {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    event.status == STATUS_OPEN && current_time < event.config.registration_deadline
}

/// Check if attendee is registered
public fun is_registered(event: &Event, attendee: address): bool {
    table::contains(&event.attendees, attendee)
}

/// Check if attendee is checked in
public fun is_checked_in(event: &Event, attendee: address): bool {
    if (table::contains(&event.attendees, attendee)) {
        let attendee_info = table::borrow(&event.attendees, attendee);
        attendee_info.checked_in
    } else {
        false
    }
}

/// Get attendee info
public fun get_attendee_info(event: &Event, attendee: address): (u64, bool, Option<u64>) {
    assert!(table::contains(&event.attendees, attendee), ENotAuthorized);
    let info = table::borrow(&event.attendees, attendee);
    (info.registered_at, info.checked_in, info.check_in_time)
}

/// Get registry info
public fun get_registry_info(registry: &EventRegistry): (u64, u64) {
    (registry.total_events, registry.platform_fee_percent)
}

/// Get event organizer
public fun get_organizer(event: &Event): address {
    event.organizer
}

/// Get ticket price
public fun get_ticket_price(event: &Event): u64 {
    event.config.ticket_price
}

/// Check if event is transferable
public fun is_transferable(event: &Event): bool {
    event.config.is_transferable
}

/// Get refund deadline
public fun get_refund_deadline(event: &Event): u64 {
    event.config.refund_deadline
}

/// Check if refund is allowed
public fun can_refund(event: &Event, ctx: &TxContext): bool {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    current_time < event.config.refund_deadline && event.status != STATUS_CANCELLED
}

/// Create event metadata
public fun create_metadata(
    title: String,
    description: String,
    walrus_blob_id: String,
    image_url: String,
    tags: vector<String>,
): EventMetadata {
    EventMetadata {
        title,
        description,
        walrus_blob_id,
        image_url,
        tags,
    }
}

/// Create event configuration
public fun create_config(
    start_time: u64,
    end_time: u64,
    registration_deadline: u64,
    capacity: u64,
    ticket_price: u64,
    requires_approval: bool,
    is_transferable: bool,
    refund_deadline: u64,
): EventConfig {
    EventConfig {
        start_time,
        end_time,
        registration_deadline,
        capacity,
        ticket_price,
        requires_approval,
        is_transferable,
        refund_deadline,
    }
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(EVENTS {}, ctx);
}
