/// Tickets Module
/// NFT ticketing with encrypted metadata and validation
module event_platform::tickets;

use std::string::String;
use sui::coin::Coin;
use sui::sui::SUI;
use sui::event;
use event_platform::events::{Self, Event};
use event_platform::users::{Self, UserProfile, BadgeRegistry};
use event_platform::payments::{Self, EventTreasury, PlatformTreasury};
use event_platform::access_control::{Self, ValidatorCap};

// ======== Error Codes ========
const ENotAuthorized: u64 = 4000;
const ERegistrationClosed: u64 = 4001;
const EInsufficientPayment: u64 = 4002;
const EInvalidEvent: u64 = 4003;
const ERefundNotAllowed: u64 = 4004;
const EAlreadyValidated: u64 = 4005;
const EInsufficientBalance: u64 = 4006;
const ETicketNotTransferable: u64 = 4007;
const EInvalidQRHash: u64 = 4008;
const EPoolExhausted: u64 = 4009;

// ======== Structs ========

/// Ticket NFT (OWNED)
public struct Ticket has key, store {
    id: UID,
    event_id: ID,
    owner: address,
    original_owner: address,
    metadata: TicketMetadata,
    validation: ValidationInfo,
    mint_time: u64,
}

public struct TicketMetadata has store, drop {
    ticket_number: u64,
    tier: String,
    encrypted_data: vector<u8>,
    seal_key_id: String,
    qr_code_hash: vector<u8>,
}

public struct ValidationInfo has store, drop {
    is_validated: bool,
    validation_time: Option<u64>,
    validator_address: Option<address>,
}

/// Ticket pool for managing capacity (SHARED)
public struct TicketPool has key {
    id: UID,
    event_id: ID,
    total_minted: u64,
    available: u64,
}

// ======== Events ========

public struct TicketMinted has copy, drop {
    ticket_id: ID,
    event_id: ID,
    owner: address,
    ticket_number: u64,
    tier: String,
    price_paid: u64,
    timestamp: u64,
}

public struct TicketValidated has copy, drop {
    ticket_id: ID,
    event_id: ID,
    owner: address,
    validator: address,
    timestamp: u64,
}

public struct TicketTransferred has copy, drop {
    ticket_id: ID,
    event_id: ID,
    from: address,
    to: address,
    timestamp: u64,
}

public struct TicketRefunded has copy, drop {
    ticket_id: ID,
    event_id: ID,
    owner: address,
    refund_amount: u64,
    timestamp: u64,
}

// ======== Public Functions ========

/// Create ticket pool for event
public(package) fun create_ticket_pool(
    event_id: ID,
    capacity: u64,
    ctx: &mut TxContext,
): TicketPool {
    TicketPool {
        id: object::new(ctx),
        event_id,
        total_minted: 0,
        available: capacity,
    }
}

/// Mint ticket (purchase)
public fun mint_ticket(
    pool: &mut TicketPool,
    event: &mut Event,
    user_profile: &mut UserProfile,
    event_treasury: &mut EventTreasury,
    platform_treasury: &mut PlatformTreasury,
    registry: &event_platform::events::EventRegistry,
    payment: Coin<SUI>,
    tier: String,
    encrypted_data: vector<u8>,
    seal_key_id: String,
    qr_code_hash: vector<u8>,
    ctx: &mut TxContext,
): Ticket {
    let sender = tx_context::sender(ctx);

    // Verify profile owner
    assert!(users::get_owner(user_profile) == sender, ENotAuthorized);

    // Verify event is open and has capacity
    assert!(events::can_register(event, ctx), ERegistrationClosed);

    // Verify pool has tickets available
    assert!(pool.available > 0, EPoolExhausted);

    // Verify event IDs match
    let event_id = object::id(event);
    assert!(pool.event_id == event_id, EInvalidEvent);
    assert!(payments::get_event_id(event_treasury) == event_id, EInvalidEvent);

    // Verify payment amount
    let ticket_price = events::get_ticket_price(event);
    let payment_value = sui::coin::value(&payment);
    assert!(payment_value == ticket_price, EInsufficientPayment);

    // Process payment (split organizer + platform fee)
    let platform_fee_percent = events::get_platform_fee_percent(registry);
    payments::process_payment(
        event_treasury,
        platform_treasury,
        sender,
        payment,
        ticket_price,
        platform_fee_percent,
        ctx,
    );

    // Register attendee in event
    events::register_attendee(event, sender, ctx);

    // Add revenue to event stats
    events::add_revenue(event, ticket_price);

    // Update user stats
    users::increment_tickets_purchased(user_profile);
    users::add_total_spent(user_profile, ticket_price);

    // Update pool
    pool.total_minted = pool.total_minted + 1;
    pool.available = pool.available - 1;

    // Create ticket
    let ticket_id = object::new(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(TicketMinted {
        ticket_id: object::uid_to_inner(&ticket_id),
        event_id,
        owner: sender,
        ticket_number: pool.total_minted,
        tier,
        price_paid: ticket_price,
        timestamp,
    });

    Ticket {
        id: ticket_id,
        event_id,
        owner: sender,
        original_owner: sender,
        metadata: TicketMetadata {
            ticket_number: pool.total_minted,
            tier,
            encrypted_data,
            seal_key_id,
            qr_code_hash,
        },
        validation: ValidationInfo {
            is_validated: false,
            validation_time: option::none(),
            validator_address: option::none(),
        },
        mint_time: timestamp,
    }
}

/// Validate ticket (check-in)
public fun validate_ticket(
    ticket: &mut Ticket,
    event: &mut Event,
    user_profile: &mut UserProfile,
    badge_registry: &mut BadgeRegistry,
    validator_cap: &ValidatorCap,
    provided_qr_hash: vector<u8>,
    ctx: &mut TxContext,
) {
    // Verify validator cap
    access_control::verify_validator(validator_cap, ticket.event_id, ctx);

    // Verify event ID matches
    let event_id = object::id(event);
    assert!(ticket.event_id == event_id, EInvalidEvent);

    // Verify profile matches ticket owner
    assert!(users::get_owner(user_profile) == ticket.owner, ENotAuthorized);

    // Verify QR code hash
    assert!(ticket.metadata.qr_code_hash == provided_qr_hash, EInvalidQRHash);

    // Verify not already validated
    assert!(!ticket.validation.is_validated, EAlreadyValidated);

    let validator = access_control::get_validator_address(validator_cap);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    // Mark as validated
    ticket.validation.is_validated = true;
    ticket.validation.validation_time = option::some(timestamp);
    ticket.validation.validator_address = option::some(validator);

    // Check-in attendee
    events::check_in_attendee(event, ticket.owner, ctx);

    // Update user stats and reputation
    users::increment_events_attended(user_profile, badge_registry, ctx);

    event::emit(TicketValidated {
        ticket_id: object::id(ticket),
        event_id,
        owner: ticket.owner,
        validator,
        timestamp,
    });
}

/// Transfer ticket to another user
public fun transfer_ticket(
    mut ticket: Ticket,
    event: &mut Event,
    sender_profile: &mut UserProfile,
    recipient: address,
    ctx: &TxContext,
) {
    let sender = tx_context::sender(ctx);

    // Verify sender owns profile
    assert!(users::get_owner(sender_profile) == sender, ENotAuthorized);

    // Verify sender owns ticket
    assert!(ticket.owner == sender, ENotAuthorized);

    // Verify transferability
    assert!(events::is_transferable(event), ETicketNotTransferable);

    // Verify event ID matches
    let event_id = object::id(event);
    assert!(ticket.event_id == event_id, EInvalidEvent);

    // Update ticket owner
    let from = ticket.owner;
    let ticket_id = object::id(&ticket);
    ticket.owner = recipient;

    // Update event attendees
    events::transfer_attendee_registration(event, from, recipient);

    // Update sender stats
    users::increment_tickets_transferred(sender_profile);

    event::emit(TicketTransferred {
        ticket_id,
        event_id,
        from,
        to: recipient,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    // Transfer NFT
    transfer::public_transfer(ticket, recipient);
}

/// Refund ticket and destroy it
public fun refund_ticket(
    ticket: Ticket,
    event: &mut Event,
    pool: &mut TicketPool,
    event_treasury: &mut EventTreasury,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);

    // Verify ALL conditions BEFORE consuming ticket
    assert!(ticket.owner == sender, ENotAuthorized);
    assert!(ticket.event_id == object::id(event), EInvalidEvent);
    assert!(events::can_refund(event, ctx), ERefundNotAllowed);
    assert!(!ticket.validation.is_validated, EAlreadyValidated);

    let ticket_price = events::get_ticket_price(event);

    // CRITICAL: Verify treasury has sufficient balance
    assert!(
        payments::get_treasury_balance(event_treasury) >= ticket_price,
        EInsufficientBalance
    );

    // Extract ticket info before destroying
    let Ticket {
        id: ticket_id,
        event_id,
        owner,
        original_owner: _,
        metadata: _,
        validation: _,
        mint_time: _,
    } = ticket;

    let ticket_id_value = object::uid_to_inner(&ticket_id);

    // Issue refund
    payments::issue_refund(event_treasury, ticket_id_value, owner, ticket_price, ctx);

    // Unregister attendee
    events::unregister_attendee(event, owner);

    // Update event stats
    events::add_refunded(event, ticket_price);

    // Update pool
    pool.available = pool.available + 1;

    event::emit(TicketRefunded {
        ticket_id: ticket_id_value,
        event_id,
        owner,
        refund_amount: ticket_price,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    // Destroy ticket UID
    object::delete(ticket_id);
}

// ======== Getter Functions ========

public fun get_event_id(ticket: &Ticket): ID {
    ticket.event_id
}

public fun get_owner(ticket: &Ticket): address {
    ticket.owner
}

public fun get_original_owner(ticket: &Ticket): address {
    ticket.original_owner
}

public fun is_validated(ticket: &Ticket): bool {
    ticket.validation.is_validated
}

public fun get_ticket_number(ticket: &Ticket): u64 {
    ticket.metadata.ticket_number
}

public fun get_tier(ticket: &Ticket): String {
    ticket.metadata.tier
}

public fun get_pool_total_minted(pool: &TicketPool): u64 {
    pool.total_minted
}

public fun get_pool_available(pool: &TicketPool): u64 {
    pool.available
}

public fun get_validation_time(ticket: &Ticket): &Option<u64> {
    &ticket.validation.validation_time
}

public fun get_validator_address(ticket: &Ticket): &Option<address> {
    &ticket.validation.validator_address
}
