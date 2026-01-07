/// Attendance Module
/// Soulbound attendance proof NFTs
module event_platform::attendance;

use std::string::String;
use sui::event;
use sui::table::{Self, Table};
use event_platform::tickets::{Self, Ticket};
use event_platform::events::Event;
use event_platform::access_control::{Self, ValidatorCap};

// ======== Error Codes ========
const ENotAuthorized: u64 = 5000;
const ETicketNotValidated: u64 = 5001;
const EAlreadyHasProof: u64 = 5002;
const ETicketEventMismatch: u64 = 5005;

// ======== Structs ========

/// Attendance proof NFT (SOULBOUND - no 'store' ability)
public struct AttendanceProof has key {
    id: UID,
    event_id: ID,
    attendee: address,
    ticket_id: ID,
    verification: VerificationData,
    metadata: AttendanceMetadata,
}

public struct VerificationData has store, drop {
    check_in_time: u64,
    check_out_time: Option<u64>,
    validator_address: address,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
}

public struct AttendanceMetadata has store, drop {
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    special_notes: Option<String>,
}

/// Attendance registry (SHARED)
public struct AttendanceRegistry has key {
    id: UID,
    total_proofs: u64,
    proofs_by_ticket: Table<ID, ID>,  // Prevent duplicates
}

// ======== Events ========

public struct AttendanceProofMinted has copy, drop {
    proof_id: ID,
    event_id: ID,
    attendee: address,
    ticket_id: ID,
    timestamp: u64,
}

public struct CheckOutRecorded has copy, drop {
    proof_id: ID,
    event_id: ID,
    attendee: address,
    check_out_time: u64,
}

// ======== Init Function ========

fun init(ctx: &mut TxContext) {
    let registry = AttendanceRegistry {
        id: object::new(ctx),
        total_proofs: 0,
        proofs_by_ticket: table::new(ctx),
    };
    transfer::share_object(registry);
}

// ======== Public Functions ========

/// Mint attendance proof for a validated ticket
public fun mint_attendance_proof(
    registry: &mut AttendanceRegistry,
    ticket: &Ticket,
    event: &Event,
    validator_cap: &ValidatorCap,
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
    special_notes: Option<String>,
    ctx: &mut TxContext,
): AttendanceProof {
    let event_id = object::id(event);

    // Verify validator
    access_control::verify_validator(validator_cap, event_id, ctx);

    // Verify ticket is for this event
    let ticket_id = object::id(ticket);
    assert!(tickets::get_event_id(ticket) == event_id, ETicketEventMismatch);

    // Verify ticket is validated
    assert!(tickets::is_validated(ticket), ETicketNotValidated);

    // Check for duplicate proofs
    assert!(!table::contains(&registry.proofs_by_ticket, ticket_id), EAlreadyHasProof);

    let attendee = tickets::get_owner(ticket);
    let validator = access_control::get_validator_address(validator_cap);

    // Get validation time from ticket (or use current time)
    let check_in_time = if (option::is_some(tickets::get_validation_time(ticket))) {
        *option::borrow(tickets::get_validation_time(ticket))
    } else {
        tx_context::epoch_timestamp_ms(ctx)
    };

    // Create proof
    let proof_id = object::new(ctx);
    let proof_id_value = object::uid_to_inner(&proof_id);

    let proof = AttendanceProof {
        id: proof_id,
        event_id,
        attendee,
        ticket_id,
        verification: VerificationData {
            check_in_time,
            check_out_time: option::none(),
            validator_address: validator,
            verification_hash,
            location_hash,
        },
        metadata: AttendanceMetadata {
            badge_image_url,
            event_title,
            event_date,
            special_notes,
        },
    };

    // Track in registry
    table::add(&mut registry.proofs_by_ticket, ticket_id, proof_id_value);
    registry.total_proofs = registry.total_proofs + 1;

    event::emit(AttendanceProofMinted {
        proof_id: proof_id_value,
        event_id,
        attendee,
        ticket_id,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    proof
}

/// Batch mint attendance proofs for multiple validated tickets
/// Note: Each ticket must be passed individually - this is a convenience wrapper
/// In practice, frontend should call mint_attendance_proof multiple times in one PTB
public fun mint_multiple_proofs(
    registry: &mut AttendanceRegistry,
    ticket1: &Ticket,
    ticket2: &Ticket,
    event: &Event,
    validator_cap: &ValidatorCap,
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
    special_notes: Option<String>,
    ctx: &mut TxContext,
): (AttendanceProof, AttendanceProof) {
    let proof1 = mint_attendance_proof(
        registry,
        ticket1,
        event,
        validator_cap,
        badge_image_url,
        event_title,
        event_date,
        verification_hash,
        location_hash,
        special_notes,
        ctx,
    );

    let proof2 = mint_attendance_proof(
        registry,
        ticket2,
        event,
        validator_cap,
        badge_image_url,
        event_title,
        event_date,
        verification_hash,
        location_hash,
        special_notes,
        ctx,
    );

    (proof1, proof2)
}

/// Record check-out time
public fun record_check_out(
    proof: &mut AttendanceProof,
    validator_cap: &ValidatorCap,
    ctx: &TxContext,
) {
    // Verify validator
    access_control::verify_validator(validator_cap, proof.event_id, ctx);

    // Verify proof owner
    let validator = access_control::get_validator_address(validator_cap);
    assert!(proof.verification.validator_address == validator, ENotAuthorized);

    let check_out_time = tx_context::epoch_timestamp_ms(ctx);
    proof.verification.check_out_time = option::some(check_out_time);

    event::emit(CheckOutRecorded {
        proof_id: object::id(proof),
        event_id: proof.event_id,
        attendee: proof.attendee,
        check_out_time,
    });
}

/// Update badge image URL (for Walrus integration)
public fun update_badge_image(
    proof: &mut AttendanceProof,
    new_image_url: String,
    ctx: &TxContext,
) {
    // Only attendee can update
    assert!(proof.attendee == tx_context::sender(ctx), ENotAuthorized);

    proof.metadata.badge_image_url = new_image_url;
}

/// Add special notes (validator only)
public fun add_special_notes(
    proof: &mut AttendanceProof,
    validator_cap: &ValidatorCap,
    notes: String,
    ctx: &TxContext,
) {
    // Verify validator
    access_control::verify_validator(validator_cap, proof.event_id, ctx);

    proof.metadata.special_notes = option::some(notes);
}

// ======== Getter Functions ========

public fun get_event_id(proof: &AttendanceProof): ID {
    proof.event_id
}

public fun get_attendee(proof: &AttendanceProof): address {
    proof.attendee
}

public fun get_ticket_id(proof: &AttendanceProof): ID {
    proof.ticket_id
}

public fun get_check_in_time(proof: &AttendanceProof): u64 {
    proof.verification.check_in_time
}

public fun get_check_out_time(proof: &AttendanceProof): &Option<u64> {
    &proof.verification.check_out_time
}

public fun get_validator(proof: &AttendanceProof): address {
    proof.verification.validator_address
}

public fun get_verification_hash(proof: &AttendanceProof): &vector<u8> {
    &proof.verification.verification_hash
}

public fun get_location_hash(proof: &AttendanceProof): &vector<u8> {
    &proof.verification.location_hash
}

public fun get_event_title(proof: &AttendanceProof): String {
    proof.metadata.event_title
}

public fun get_event_date(proof: &AttendanceProof): u64 {
    proof.metadata.event_date
}

public fun get_badge_image_url(proof: &AttendanceProof): String {
    proof.metadata.badge_image_url
}

public fun get_special_notes(proof: &AttendanceProof): &Option<String> {
    &proof.metadata.special_notes
}

public fun has_proof_for_ticket(registry: &AttendanceRegistry, ticket_id: ID): bool {
    table::contains(&registry.proofs_by_ticket, ticket_id)
}

public fun get_total_proofs(registry: &AttendanceRegistry): u64 {
    registry.total_proofs
}
