/// Tickets Module
/// Ticket NFT minting, validation, and transfers
module event_platform::tickets;

use event_platform::access_control::{Self, EventOrganizerCap, ValidatorCap};
use event_platform::events::{Self, Event};
use event_platform::payments::{Self, EventTreasury, PlatformTreasury, Payment};
use std::option::{Self, Option};
use std::string::String;
use sui::coin::Coin;
use sui::event;
use sui::object::{Self, UID, ID};
use sui::sui::SUI;
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EInvalidEvent: u64 = 2;
const ETicketNotTransferable: u64 = 3;
const EAlreadyValidated: u64 = 4;
const ERefundNotAllowed: u64 = 5;
const EInvalidQRHash: u64 = 6;
const EPoolFull: u64 = 7;

// === One-Time-Witness ===
public struct TICKETS has drop {}

// === Main Structs ===

/// Ticket NFT (owned by user)
public struct Ticket has key, store {
    id: UID,
    event_id: ID,
    owner: address,
    original_owner: address,
    metadata: TicketMetadata,
    validation: ValidationInfo,
    mint_time: u64,
}

/// Nested ticket metadata
public struct TicketMetadata has drop, store {
    ticket_number: u64,
    tier: String,
    encrypted_data: vector<u8>, // Seal encrypted
    seal_key_id: String,
    qr_code_hash: vector<u8>,
}

/// Nested validation info
public struct ValidationInfo has drop, store {
    is_validated: bool,
    validation_time: Option<u64>,
    validator_address: Option<address>,
}

/// Shared ticket pool for events
public struct TicketPool has key {
    id: UID,
    event_id: ID,
    total_minted: u64,
    available: u64,
}

// === Event Logs ===

public struct TicketMinted has copy, drop {
    ticket_id: ID,
    event_id: ID,
    owner: address,
    ticket_number: u64,
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

// === Public Functions ===

/// Create ticket pool for an event
public fun create_ticket_pool(event: &Event, cap: &EventOrganizerCap, ctx: &mut TxContext) {
    // Verify organizer owns this event
    assert!(access_control::verify_organizer(cap, object::id(event)), ENotAuthorized);

    let config = events::get_event_config(event);
    let pool = TicketPool {
        id: object::new(ctx),
        event_id: object::id(event),
        total_minted: 0,
        available: config.capacity,
    };

    transfer::share_object(pool);
}

/// Mint ticket to user
public fun mint_ticket(
    pool: &mut TicketPool,
    event: &mut Event,
    event_treasury: &mut EventTreasury,
    platform_treasury: &mut PlatformTreasury,
    payment: Coin<SUI>,
    tier: String,
    encrypted_data: vector<u8>,
    seal_key_id: String,
    qr_code_hash: vector<u8>,
    platform_fee_percent: u64,
    ctx: &mut TxContext,
): (Ticket, Payment) {
    // Verify pool matches event
    assert!(pool.event_id == object::id(event), EInvalidEvent);
    assert!(pool.event_id == payments::get_treasury_event_id(event_treasury), EInvalidEvent);

    // Check availability
    assert!(pool.available > 0, EPoolFull);

    let owner = tx_context::sender(ctx);
    let ticket_price = events::get_ticket_price(event);

    // Process payment
    let payment_record = payments::process_payment(
        event_treasury,
        platform_treasury,
        owner,
        payment,
        ticket_price,
        platform_fee_percent,
        ctx,
    );

    // Register attendee in event
    events::register_attendee(event, owner, ctx);

    // Add revenue to event stats
    events::add_revenue(event, ticket_price);

    // Update pool
    pool.total_minted = pool.total_minted + 1;
    pool.available = pool.available - 1;

    // Create ticket metadata
    let metadata = TicketMetadata {
        ticket_number: pool.total_minted,
        tier,
        encrypted_data,
        seal_key_id,
        qr_code_hash,
    };

    // Create validation info
    let validation = ValidationInfo {
        is_validated: false,
        validation_time: option::none(),
        validator_address: option::none(),
    };

    // Create ticket NFT
    let ticket_uid = object::new(ctx);
    let ticket_id = object::uid_to_inner(&ticket_uid);
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    let ticket = Ticket {
        id: ticket_uid,
        event_id: pool.event_id,
        owner,
        original_owner: owner,
        metadata,
        validation,
        mint_time: current_time,
    };

    event::emit(TicketMinted {
        ticket_id,
        event_id: pool.event_id,
        owner,
        ticket_number: pool.total_minted,
        timestamp: current_time,
    });

    (ticket, payment_record)
}

/// Validate ticket at check-in
public fun validate_ticket(
    ticket: &mut Ticket,
    event: &mut Event,
    validator_cap: &ValidatorCap,
    ctx: &TxContext,
) {
    // Verify validator has permission for this event
    assert!(access_control::verify_validator(validator_cap, ticket.event_id), ENotAuthorized);
    assert!(ticket.event_id == object::id(event), EInvalidEvent);

    // Check if already validated
    assert!(!ticket.validation.is_validated, EAlreadyValidated);

    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let validator = tx_context::sender(ctx);

    // Mark as validated
    ticket.validation.is_validated = true;
    ticket.validation.validation_time = option::some(current_time);
    ticket.validation.validator_address = option::some(validator);

    // Mark attendee as checked in
    events::check_in_attendee(event, ticket.owner, ctx);

    event::emit(TicketValidated {
        ticket_id: object::id(ticket),
        event_id: ticket.event_id,
        owner: ticket.owner,
        validator,
        timestamp: current_time,
    });
}

/// Transfer ticket (if allowed by event)
public fun transfer_ticket(ticket: Ticket, event: &Event, recipient: address, ctx: &TxContext) {
    // Check if event allows transfers
    assert!(events::is_transferable(event), ETicketNotTransferable);
    assert!(ticket.event_id == object::id(event), EInvalidEvent);

    let from = ticket.owner;

    // Update owner
    ticket.owner = recipient;

    event::emit(TicketTransferred {
        ticket_id: object::id(&ticket),
        from,
        to: recipient,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    transfer::public_transfer(ticket, recipient);
}

/// Refund ticket (before event starts)
public fun refund_ticket(
    ticket: Ticket,
    event: &mut Event,
    pool: &mut TicketPool,
    event_treasury: &mut EventTreasury,
    ctx: &mut TxContext,
): Payment {
    // Verify ticket belongs to this event
    assert!(ticket.event_id == object::id(event), EInvalidEvent);
    assert!(pool.event_id == object::id(event), EInvalidEvent);
    assert!(ticket.event_id == payments::get_treasury_event_id(event_treasury), EInvalidEvent);

    // Check if refund is allowed
    assert!(events::can_refund(event, ctx), ERefundNotAllowed);

    // Ticket must not be validated
    assert!(!ticket.validation.is_validated, EAlreadyValidated);

    let ticket_price = events::get_ticket_price(event);
    let owner = ticket.owner;
    let ticket_id = object::id(&ticket);

    // Calculate refund amount (100% for now, can be adjusted)
    let refund_amount = ticket_price;

    // Issue refund
    let payment_record = payments::issue_refund(
        event_treasury,
        ticket_id,
        owner,
        refund_amount,
        ctx,
    );

    // Unregister attendee
    events::unregister_attendee(event, owner);

    // Update event stats
    events::add_refunded(event, refund_amount);

    // Update pool
    pool.available = pool.available + 1;

    event::emit(TicketRefunded {
        ticket_id,
        event_id: ticket.event_id,
        owner,
        refund_amount,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    // Destroy ticket
    let Ticket {
        id,
        event_id: _,
        owner: _,
        original_owner: _,
        metadata: _,
        validation: _,
        mint_time: _,
    } = ticket;
    object::delete(id);

    payment_record
}

// === View Functions ===

/// Get ticket info
public fun get_ticket_info(ticket: &Ticket): (ID, String, address, u64, bool, u64) {
    (
        ticket.event_id,
        ticket.metadata.tier,
        ticket.owner,
        ticket.mint_time,
        ticket.validation.is_validated,
        ticket.metadata.ticket_number,
    )
}

/// Get ticket metadata
public fun get_ticket_metadata(ticket: &Ticket): &TicketMetadata {
    &ticket.metadata
}

/// Get validation info
public fun get_validation_info(ticket: &Ticket): (bool, Option<u64>, Option<address>) {
    (
        ticket.validation.is_validated,
        ticket.validation.validation_time,
        ticket.validation.validator_address,
    )
}

/// Check if ticket is validated
public fun is_validated(ticket: &Ticket): bool {
    ticket.validation.is_validated
}

/// Get ticket owner
public fun get_owner(ticket: &Ticket): address {
    ticket.owner
}

/// Get original owner
public fun get_original_owner(ticket: &Ticket): address {
    ticket.original_owner
}

/// Get ticket number
public fun get_ticket_number(ticket: &Ticket): u64 {
    ticket.metadata.ticket_number
}

/// Get encrypted data
public fun get_encrypted_data(ticket: &Ticket): &vector<u8> {
    &ticket.metadata.encrypted_data
}

/// Get QR code hash
public fun get_qr_code_hash(ticket: &Ticket): &vector<u8> {
    &ticket.metadata.qr_code_hash
}

/// Get pool stats
public fun get_pool_stats(pool: &TicketPool): (u64, u64) {
    (pool.total_minted, pool.available)
}

/// Get pool event ID
public fun get_pool_event_id(pool: &TicketPool): ID {
    pool.event_id
}

// === Test Functions ===
#[test_only]
public fun create_test_ticket(
    event_id: ID,
    owner: address,
    ticket_number: u64,
    ctx: &mut TxContext,
): Ticket {
    let metadata = TicketMetadata {
        ticket_number,
        tier: std::string::utf8(b"General"),
        encrypted_data: std::vector::empty(),
        seal_key_id: std::string::utf8(b"test_key"),
        qr_code_hash: std::vector::empty(),
    };

    let validation = ValidationInfo {
        is_validated: false,
        validation_time: option::none(),
        validator_address: option::none(),
    };

    Ticket {
        id: object::new(ctx),
        event_id,
        owner,
        original_owner: owner,
        metadata,
        validation,
        mint_time: tx_context::epoch_timestamp_ms(ctx),
    }
}
