/// Event Platform Module
/// A decentralized event ticketing platform with Walrus integration for image storage
module event_platform::event;

use std::string::String;
use sui::balance::{Self, Balance};
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::object::{Self, UID, ID};
use sui::sui::SUI;
use sui::table::{Self, Table};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EEventFull: u64 = 2;
const EInvalidTime: u64 = 3;
const EInsufficientPayment: u64 = 4;
const EEventNotOpen: u64 = 5;
const EEventAlreadyStarted: u64 = 6;
const EAlreadyRegistered: u64 = 7;
const EInvalidStatus: u64 = 8;

// === Constants ===
const STATUS_DRAFT: u8 = 0;
const STATUS_OPEN: u8 = 1;
const STATUS_CLOSED: u8 = 2;
const STATUS_CANCELLED: u8 = 3;

const PLATFORM_FEE_PERCENT: u64 = 5; // 5% platform fee

// === One-Time-Witness ===
/// One-Time-Witness for module initialization
public struct EVENT has drop {}

// === Main Structs ===

/// Global registry for the event platform (shared object)
public struct EventRegistry has key {
    id: UID,
    total_events: u64,
    platform_fee_percent: u64,
    platform_balance: Balance<SUI>,
    admin: address,
}

/// Main Event object (shared object)
public struct Event has key, store {
    id: UID,
    organizer: address,
    metadata: EventMetadata,
    config: EventConfig,
    stats: EventStats,
    status: u8,
    revenue: Balance<SUI>,
    attendees: Table<address, bool>,
}

/// Event metadata stored inside Event
public struct EventMetadata has drop, store {
    title: String,
    description: String,
    location: String,
    walrus_blob_id: String, // Walrus storage reference for event image
    category: String,
}

/// Event configuration stored inside Event
public struct EventConfig has drop, store {
    start_time: u64,
    end_time: u64,
    registration_deadline: u64,
    capacity: u64,
    ticket_price: u64,
    requires_approval: bool,
}

/// Copyable event statistics
public struct EventStats has copy, drop, store {
    registered: u64,
    checked_in: u64,
    total_revenue: u64,
}

/// Capability to manage an event (owned by organizer)
public struct EventOrganizerCap has key, store {
    id: UID,
    event_id: ID,
}

/// Ticket NFT given to attendees
public struct Ticket has key, store {
    id: UID,
    event_id: ID,
    event_title: String,
    attendee: address,
    purchase_time: u64,
    checked_in: bool,
    ticket_number: u64,
}

// === Events (Logs) ===

public struct EventCreated has copy, drop {
    event_id: ID,
    organizer: address,
    title: String,
    start_time: u64,
}

public struct EventUpdated has copy, drop {
    event_id: ID,
    title: String,
}

public struct EventStatusChanged has copy, drop {
    event_id: ID,
    old_status: u8,
    new_status: u8,
}

public struct TicketPurchased has copy, drop {
    event_id: ID,
    ticket_id: ID,
    attendee: address,
    price: u64,
}

public struct AttendeeCheckedIn has copy, drop {
    event_id: ID,
    attendee: address,
    ticket_id: ID,
}

// === Init Function ===

/// Initialize the module with a shared registry
fun init(witness: EVENT, ctx: &mut TxContext) {
    let registry = EventRegistry {
        id: object::new(ctx),
        total_events: 0,
        platform_fee_percent: PLATFORM_FEE_PERCENT,
        platform_balance: balance::zero(),
        admin: tx_context::sender(ctx),
    };
    transfer::share_object(registry);
}

// === Public Functions ===

/// Create a new event
public fun create_event(
    registry: &mut EventRegistry,
    title: String,
    description: String,
    location: String,
    walrus_blob_id: String,
    category: String,
    start_time: u64,
    end_time: u64,
    registration_deadline: u64,
    capacity: u64,
    ticket_price: u64,
    requires_approval: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): EventOrganizerCap {
    // Validate times
    let current_time = clock::timestamp_ms(clock);
    assert!(start_time > current_time, EInvalidTime);
    assert!(end_time > start_time, EInvalidTime);
    assert!(registration_deadline <= start_time, EInvalidTime);
    assert!(registration_deadline > current_time, EInvalidTime);

    // Create event metadata
    let metadata = EventMetadata {
        title,
        description,
        location,
        walrus_blob_id,
        category,
    };

    // Create event config
    let config = EventConfig {
        start_time,
        end_time,
        registration_deadline,
        capacity,
        ticket_price,
        requires_approval,
    };

    // Create event stats
    let stats = EventStats {
        registered: 0,
        checked_in: 0,
        total_revenue: 0,
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
        revenue: balance::zero(),
        attendees: table::new(ctx),
    };

    // Share the event object
    transfer::share_object(event_obj);

    // Update registry
    registry.total_events = registry.total_events + 1;

    // Create organizer capability
    let cap = EventOrganizerCap {
        id: object::new(ctx),
        event_id,
    };

    // Emit event
    event::emit(EventCreated {
        event_id,
        organizer: tx_context::sender(ctx),
        title: title,
        start_time,
    });

    cap
}

/// Update event metadata (only by organizer)
public fun update_event_metadata(
    event: &mut Event,
    cap: &EventOrganizerCap,
    title: String,
    description: String,
    location: String,
    walrus_blob_id: String,
    category: String,
) {
    // Verify ownership
    assert!(object::id(event) == cap.event_id, ENotAuthorized);

    // Update metadata
    event.metadata.title = title;
    event.metadata.description = description;
    event.metadata.location = location;
    event.metadata.walrus_blob_id = walrus_blob_id;
    event.metadata.category = category;

    // Emit event
    event::emit(EventUpdated {
        event_id: object::id(event),
        title,
    });
}

/// Change event status (only by organizer)
public fun change_event_status(
    event: &mut Event,
    cap: &EventOrganizerCap,
    new_status: u8,
    clock: &Clock,
) {
    // Verify ownership
    assert!(object::id(event) == cap.event_id, ENotAuthorized);

    // Validate status
    assert!(new_status <= STATUS_CANCELLED, EInvalidStatus);

    // If opening event, check time
    if (new_status == STATUS_OPEN) {
        let current_time = clock::timestamp_ms(clock);
        assert!(current_time < event.config.registration_deadline, EInvalidTime);
    };

    let old_status = event.status;
    event.status = new_status;

    // Emit event
    event::emit(EventStatusChanged {
        event_id: object::id(event),
        old_status,
        new_status,
    });
}

/// Purchase a ticket for an event
public fun purchase_ticket(
    event: &mut Event,
    registry: &mut EventRegistry,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Ticket {
    let attendee = tx_context::sender(ctx);
    let current_time = clock::timestamp_ms(clock);

    // Validate event status
    assert!(event.status == STATUS_OPEN, EEventNotOpen);

    // Check registration deadline
    assert!(current_time < event.config.registration_deadline, EInvalidTime);

    // Check capacity
    assert!(event.stats.registered < event.config.capacity, EEventFull);

    // Check if already registered
    assert!(!table::contains(&event.attendees, attendee), EAlreadyRegistered);

    // Validate payment
    let payment_amount = coin::value(&payment);
    assert!(payment_amount >= event.config.ticket_price, EInsufficientPayment);

    // Calculate platform fee
    let platform_fee = (event.config.ticket_price * registry.platform_fee_percent) / 100;
    let organizer_amount = event.config.ticket_price - platform_fee;

    // Split payment
    let mut payment_balance = coin::into_balance(payment);
    let platform_fee_balance = balance::split(&mut payment_balance, platform_fee);
    let organizer_balance = balance::split(&mut payment_balance, organizer_amount);

    // Add to balances
    balance::join(&mut registry.platform_balance, platform_fee_balance);
    balance::join(&mut event.revenue, organizer_balance);

    // Handle excess payment (refund)
    if (balance::value(&payment_balance) > 0) {
        transfer::public_transfer(
            coin::from_balance(payment_balance, ctx),
            attendee,
        );
    } else {
        balance::destroy_zero(payment_balance);
    };

    // Update event stats
    event.stats.registered = event.stats.registered + 1;
    event.stats.total_revenue = event.stats.total_revenue + event.config.ticket_price;

    // Mark attendee as registered
    table::add(&mut event.attendees, attendee, false);

    // Create ticket NFT
    let ticket_uid = object::new(ctx);
    let ticket_id = object::uid_to_inner(&ticket_uid);

    let ticket = Ticket {
        id: ticket_uid,
        event_id: object::id(event),
        event_title: event.metadata.title,
        attendee,
        purchase_time: current_time,
        checked_in: false,
        ticket_number: event.stats.registered,
    };

    // Emit event
    event::emit(TicketPurchased {
        event_id: object::id(event),
        ticket_id,
        attendee,
        price: event.config.ticket_price,
    });

    ticket
}

/// Check in attendee (only by organizer)
public fun check_in_attendee(event: &mut Event, ticket: &mut Ticket, cap: &EventOrganizerCap) {
    // Verify ownership
    assert!(object::id(event) == cap.event_id, ENotAuthorized);

    // Verify ticket belongs to this event
    assert!(ticket.event_id == object::id(event), ENotAuthorized);

    // Mark as checked in
    if (!ticket.checked_in) {
        ticket.checked_in = true;
        event.stats.checked_in = event.stats.checked_in + 1;

        // Update attendee table
        *table::borrow_mut(&mut event.attendees, ticket.attendee) = true;

        // Emit event
        event::emit(AttendeeCheckedIn {
            event_id: object::id(event),
            attendee: ticket.attendee,
            ticket_id: object::id(ticket),
        });
    };
}

/// Withdraw event revenue (only by organizer)
public fun withdraw_revenue(event: &mut Event, cap: &EventOrganizerCap, ctx: &mut TxContext) {
    // Verify ownership
    assert!(object::id(event) == cap.event_id, ENotAuthorized);

    let amount = balance::value(&event.revenue);
    if (amount > 0) {
        let withdrawn = coin::take(&mut event.revenue, amount, ctx);
        transfer::public_transfer(withdrawn, event.organizer);
    };
}

/// Withdraw platform fees (only by admin)
public fun withdraw_platform_fees(registry: &mut EventRegistry, ctx: &mut TxContext) {
    // Verify admin
    assert!(tx_context::sender(ctx) == registry.admin, ENotAuthorized);

    let amount = balance::value(&registry.platform_balance);
    if (amount > 0) {
        let withdrawn = coin::take(&mut registry.platform_balance, amount, ctx);
        transfer::public_transfer(withdrawn, registry.admin);
    };
}

// === View Functions ===

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
public fun get_event_stats(event: &Event): (u64, u64, u64) {
    (event.stats.registered, event.stats.checked_in, event.stats.total_revenue)
}

/// Get ticket info
public fun get_ticket_info(ticket: &Ticket): (ID, String, address, u64, bool, u64) {
    (
        ticket.event_id,
        ticket.event_title,
        ticket.attendee,
        ticket.purchase_time,
        ticket.checked_in,
        ticket.ticket_number,
    )
}

/// Check if address is registered for event
public fun is_registered(event: &Event, attendee: address): bool {
    table::contains(&event.attendees, attendee)
}

/// Get registry info
public fun get_registry_info(registry: &EventRegistry): (u64, u64, u64) {
    (
        registry.total_events,
        registry.platform_fee_percent,
        balance::value(&registry.platform_balance),
    )
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(EVENT {}, ctx);
}
