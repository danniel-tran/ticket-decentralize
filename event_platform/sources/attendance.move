/// Attendance Module
/// Attendance proof NFTs and verification
module event_platform::attendance;

use event_platform::access_control::{Self, ValidatorCap};
use event_platform::events::Event;
use event_platform::tickets::{Self, Ticket};
use std::option::{Self, Option};
use std::string::String;
use sui::event;
use sui::object::{Self, UID, ID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const ETicketNotValidated: u64 = 2;
const EInvalidEvent: u64 = 3;
const EAlreadyHasProof: u64 = 4;

// === One-Time-Witness ===
public struct ATTENDANCE has drop {}

// === Main Structs ===

/// Attendance proof NFT (soulbound)
public struct AttendanceProof has key {
    id: UID,
    event_id: ID,
    attendee: address,
    ticket_id: ID,
    verification: VerificationData,
    metadata: AttendanceMetadata,
    is_soulbound: bool,
}

/// Nested verification data
public struct VerificationData has drop, store {
    check_in_time: u64,
    check_out_time: Option<u64>,
    validator_address: address,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
}

/// Nested attendance metadata
public struct AttendanceMetadata has drop, store {
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    special_notes: Option<String>,
}

/// Shared registry for queries
public struct AttendanceRegistry has key {
    id: UID,
    total_proofs: u64,
}

// === Event Logs ===

public struct AttendanceRecorded has copy, drop {
    proof_id: ID,
    event_id: ID,
    attendee: address,
    timestamp: u64,
}

public struct BatchAttendanceRecorded has copy, drop {
    event_id: ID,
    count: u64,
    timestamp: u64,
}

// === Init Function ===

/// Initialize attendance registry
fun init(_witness: ATTENDANCE, ctx: &mut TxContext) {
    let registry = AttendanceRegistry {
        id: object::new(ctx),
        total_proofs: 0,
    };
    transfer::share_object(registry);
}

// === Public Functions ===

/// Mint attendance proof for a validated ticket
public fun mint_attendance_proof(
    registry: &mut AttendanceRegistry,
    ticket: &Ticket,
    event: &Event,
    validator_cap: &ValidatorCap,
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    special_notes: Option<String>,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
    ctx: &mut TxContext,
): AttendanceProof {
    // Verify validator has permission
    assert!(access_control::verify_validator(validator_cap, object::id(event)), ENotAuthorized);

    // Verify ticket is validated
    assert!(tickets::is_validated(ticket), ETicketNotValidated);

    // Verify ticket belongs to this event
    let (ticket_event_id, _, ticket_owner, _, _, _) = tickets::get_ticket_info(ticket);
    assert!(ticket_event_id == object::id(event), EInvalidEvent);

    let current_time = tx_context::epoch_timestamp_ms(ctx);
    let validator = tx_context::sender(ctx);

    // Create verification data
    let verification = VerificationData {
        check_in_time: current_time,
        check_out_time: option::none(),
        validator_address: validator,
        verification_hash,
        location_hash,
    };

    // Create attendance metadata
    let metadata = AttendanceMetadata {
        badge_image_url,
        event_title,
        event_date,
        special_notes,
    };

    // Create attendance proof
    let proof_uid = object::new(ctx);
    let proof_id = object::uid_to_inner(&proof_uid);

    let proof = AttendanceProof {
        id: proof_uid,
        event_id: object::id(event),
        attendee: ticket_owner,
        ticket_id: object::id(ticket),
        verification,
        metadata,
        is_soulbound: true,
    };

    // Update registry
    registry.total_proofs = registry.total_proofs + 1;

    event::emit(AttendanceRecorded {
        proof_id,
        event_id: object::id(event),
        attendee: ticket_owner,
        timestamp: current_time,
    });

    proof
}

/// Batch mint attendance proofs (for efficiency)
public fun batch_mint_attendance(
    registry: &mut AttendanceRegistry,
    tickets: vector<&Ticket>,
    event: &Event,
    validator_cap: &ValidatorCap,
    badge_image_url: String,
    event_title: String,
    event_date: u64,
    verification_hash: vector<u8>,
    location_hash: vector<u8>,
    ctx: &mut TxContext,
): vector<AttendanceProof> {
    // Verify validator has permission
    assert!(access_control::verify_validator(validator_cap, object::id(event)), ENotAuthorized);

    let count = std::vector::length(&tickets);
    let mut proofs = std::vector::empty<AttendanceProof>();
    let mut i = 0;

    while (i < count) {
        let ticket = std::vector::borrow(&tickets, i);

        // Verify ticket is validated
        assert!(tickets::is_validated(ticket), ETicketNotValidated);

        // Verify ticket belongs to this event
        let (ticket_event_id, _, ticket_owner, _, _, _) = tickets::get_ticket_info(ticket);
        assert!(ticket_event_id == object::id(event), EInvalidEvent);

        let current_time = tx_context::epoch_timestamp_ms(ctx);
        let validator = tx_context::sender(ctx);

        // Create verification data
        let verification = VerificationData {
            check_in_time: current_time,
            check_out_time: option::none(),
            validator_address: validator,
            verification_hash,
            location_hash,
        };

        // Create attendance metadata
        let metadata = AttendanceMetadata {
            badge_image_url,
            event_title,
            event_date,
            special_notes: option::none(),
        };

        // Create attendance proof
        let proof_uid = object::new(ctx);
        let proof_id = object::uid_to_inner(&proof_uid);

        let proof = AttendanceProof {
            id: proof_uid,
            event_id: object::id(event),
            attendee: ticket_owner,
            ticket_id: object::id(ticket),
            verification,
            metadata,
            is_soulbound: true,
        };

        event::emit(AttendanceRecorded {
            proof_id,
            event_id: object::id(event),
            attendee: ticket_owner,
            timestamp: current_time,
        });

        std::vector::push_back(&mut proofs, proof);
        i = i + 1;
    };

    // Update registry
    registry.total_proofs = registry.total_proofs + count;

    event::emit(BatchAttendanceRecorded {
        event_id: object::id(event),
        count,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    proofs
}

/// Record check-out time
public fun record_checkout(
    proof: &mut AttendanceProof,
    validator_cap: &ValidatorCap,
    ctx: &TxContext,
) {
    // Verify validator has permission
    assert!(access_control::verify_validator(validator_cap, proof.event_id), ENotAuthorized);

    let current_time = tx_context::epoch_timestamp_ms(ctx);
    proof.verification.check_out_time = option::some(current_time);
}

/// Verify attendance proof authenticity
public fun verify_attendance(proof: &AttendanceProof): bool {
    // Basic verification - proof exists and has valid structure
    // In production, could verify cryptographic signatures
    proof.is_soulbound
}

/// Add special notes to attendance proof
public fun add_special_notes(
    proof: &mut AttendanceProof,
    validator_cap: &ValidatorCap,
    notes: String,
) {
    // Verify validator has permission
    assert!(access_control::verify_validator(validator_cap, proof.event_id), ENotAuthorized);
    proof.metadata.special_notes = option::some(notes);
}

// === View Functions ===

/// Get proof details
public fun get_proof_info(proof: &AttendanceProof): (ID, address, ID, u64, bool) {
    (
        proof.event_id,
        proof.attendee,
        proof.ticket_id,
        proof.verification.check_in_time,
        proof.is_soulbound,
    )
}

/// Get verification data
public fun get_verification_data(proof: &AttendanceProof): (u64, Option<u64>, address) {
    (
        proof.verification.check_in_time,
        proof.verification.check_out_time,
        proof.verification.validator_address,
    )
}

/// Get metadata
public fun get_attendance_metadata(proof: &AttendanceProof): &AttendanceMetadata {
    &proof.metadata
}

/// Get badge image URL
public fun get_badge_image_url(proof: &AttendanceProof): String {
    proof.metadata.badge_image_url
}

/// Get event title from proof
public fun get_event_title(proof: &AttendanceProof): String {
    proof.metadata.event_title
}

/// Get special notes
public fun get_special_notes(proof: &AttendanceProof): Option<String> {
    proof.metadata.special_notes
}

/// Get attendee address
public fun get_attendee(proof: &AttendanceProof): address {
    proof.attendee
}

/// Get event ID from proof
public fun get_event_id(proof: &AttendanceProof): ID {
    proof.event_id
}

/// Get check-in time
public fun get_check_in_time(proof: &AttendanceProof): u64 {
    proof.verification.check_in_time
}

/// Get check-out time
public fun get_check_out_time(proof: &AttendanceProof): Option<u64> {
    proof.verification.check_out_time
}

/// Get registry stats
public fun get_registry_stats(registry: &AttendanceRegistry): u64 {
    registry.total_proofs
}

/// Check if proof is soulbound
public fun is_soulbound(proof: &AttendanceProof): bool {
    proof.is_soulbound
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ATTENDANCE {}, ctx);
}

#[test_only]
public fun create_test_proof(
    event_id: ID,
    attendee: address,
    ticket_id: ID,
    ctx: &mut TxContext,
): AttendanceProof {
    let verification = VerificationData {
        check_in_time: tx_context::epoch_timestamp_ms(ctx),
        check_out_time: option::none(),
        validator_address: tx_context::sender(ctx),
        verification_hash: std::vector::empty(),
        location_hash: std::vector::empty(),
    };

    let metadata = AttendanceMetadata {
        badge_image_url: std::string::utf8(b"https://example.com/badge.png"),
        event_title: std::string::utf8(b"Test Event"),
        event_date: tx_context::epoch_timestamp_ms(ctx),
        special_notes: option::none(),
    };

    AttendanceProof {
        id: object::new(ctx),
        event_id,
        attendee,
        ticket_id,
        verification,
        metadata,
        is_soulbound: true,
    }
}
