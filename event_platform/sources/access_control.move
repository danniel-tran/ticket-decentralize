/// Access Control Module
/// Manages capabilities and permissions for the event platform
module event_platform::access_control;

use sui::event;
use sui::object::{Self, UID, ID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EInvalidPermission: u64 = 2;
const EInvalidAdminLevel: u64 = 3;
const EInvalidEventId: u64 = 4;
const EInsufficientSignatures: u64 = 5;

// === Constants ===
const ADMIN_LEVEL_SUPER: u8 = 0;
const ADMIN_LEVEL_MODERATOR: u8 = 1;

// === One-Time-Witness ===
public struct ACCESS_CONTROL has drop {}

// === Capability Structs ===

/// Platform admin capability
public struct PlatformAdminCap has key {
    id: UID,
    admin_level: u8,
}

/// Event organizer capability
public struct EventOrganizerCap has key, store {
    id: UID,
    event_id: ID,
    permissions: OrganizerPermissions,
}

/// Nested permissions for organizers
public struct OrganizerPermissions has copy, drop, store {
    can_update_event: bool,
    can_cancel_event: bool,
    can_approve_registrations: bool,
    can_withdraw_funds: bool,
}

/// Validator capability (for check-in)
public struct ValidatorCap has key, store {
    id: UID,
    event_id: ID,
    validator_address: address,
    granted_by: address,
}

/// Multi-sig organizer (for co-organized events)
public struct MultiSigOrganizer has key {
    id: UID,
    event_id: ID,
    organizers: vector<address>,
    required_approvals: u64,
    approvals: vector<address>,
}

// === Event Logs ===

public struct CapabilityGranted has copy, drop {
    cap_type: vector<u8>,
    recipient: address,
    event_id: ID,
    timestamp: u64,
}

public struct CapabilityRevoked has copy, drop {
    cap_type: vector<u8>,
    event_id: ID,
    timestamp: u64,
}

public struct MultiSigCreated has copy, drop {
    event_id: ID,
    organizers: vector<address>,
    required_approvals: u64,
}

// === Init Function ===

/// Initialize the module and grant admin capability
fun init(_witness: ACCESS_CONTROL, ctx: &mut TxContext) {
    let admin_cap = PlatformAdminCap {
        id: object::new(ctx),
        admin_level: ADMIN_LEVEL_SUPER,
    };
    transfer::transfer(admin_cap, tx_context::sender(ctx));
}

// === Public Functions ===

/// Grant organizer capability with full permissions
public fun grant_organizer_cap(event_id: ID, ctx: &mut TxContext): EventOrganizerCap {
    let permissions = OrganizerPermissions {
        can_update_event: true,
        can_cancel_event: true,
        can_approve_registrations: true,
        can_withdraw_funds: true,
    };

    let cap = EventOrganizerCap {
        id: object::new(ctx),
        event_id,
        permissions,
    };

    event::emit(CapabilityGranted {
        cap_type: b"EventOrganizerCap",
        recipient: tx_context::sender(ctx),
        event_id,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    cap
}

/// Grant organizer capability with custom permissions
public fun grant_organizer_cap_custom(
    event_id: ID,
    permissions: OrganizerPermissions,
    ctx: &mut TxContext,
): EventOrganizerCap {
    let cap = EventOrganizerCap {
        id: object::new(ctx),
        event_id,
        permissions,
    };

    event::emit(CapabilityGranted {
        cap_type: b"EventOrganizerCap",
        recipient: tx_context::sender(ctx),
        event_id,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    cap
}

/// Grant validator capability
public fun grant_validator_cap(
    event_id: ID,
    validator: address,
    organizer_cap: &EventOrganizerCap,
    ctx: &mut TxContext,
): ValidatorCap {
    // Verify organizer owns this event
    assert!(organizer_cap.event_id == event_id, ENotAuthorized);

    let cap = ValidatorCap {
        id: object::new(ctx),
        event_id,
        validator_address: validator,
        granted_by: tx_context::sender(ctx),
    };

    event::emit(CapabilityGranted {
        cap_type: b"ValidatorCap",
        recipient: validator,
        event_id,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    cap
}

/// Revoke validator capability
public fun revoke_validator_cap(cap: ValidatorCap, ctx: &TxContext) {
    let ValidatorCap { id, event_id, validator_address: _, granted_by: _ } = cap;

    event::emit(CapabilityRevoked {
        cap_type: b"ValidatorCap",
        event_id,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    object::delete(id);
}

/// Create multi-sig for co-organized events
public fun create_multisig(
    event_id: ID,
    organizers: vector<address>,
    required_approvals: u64,
    ctx: &mut TxContext,
): MultiSigOrganizer {
    let organizer_count = std::vector::length(&organizers);
    assert!(
        required_approvals > 0 && required_approvals <= organizer_count,
        EInsufficientSignatures,
    );

    let multisig = MultiSigOrganizer {
        id: object::new(ctx),
        event_id,
        organizers,
        required_approvals,
        approvals: std::vector::empty(),
    };

    event::emit(MultiSigCreated {
        event_id,
        organizers: multisig.organizers,
        required_approvals,
    });

    multisig
}

/// Add approval to multi-sig
public fun add_multisig_approval(multisig: &mut MultiSigOrganizer, ctx: &TxContext) {
    let sender = tx_context::sender(ctx);

    // Check if sender is an organizer
    assert!(std::vector::contains(&multisig.organizers, &sender), ENotAuthorized);

    // Check if already approved
    if (!std::vector::contains(&multisig.approvals, &sender)) {
        std::vector::push_back(&mut multisig.approvals, sender);
    };
}

/// Check if multi-sig has enough approvals
public fun has_sufficient_approvals(multisig: &MultiSigOrganizer): bool {
    std::vector::length(&multisig.approvals) >= multisig.required_approvals
}

/// Reset multi-sig approvals
public fun reset_multisig_approvals(multisig: &mut MultiSigOrganizer) {
    multisig.approvals = std::vector::empty();
}

/// Grant additional admin capability (only by super admin)
public fun grant_admin_cap(
    _admin_cap: &PlatformAdminCap,
    recipient: address,
    admin_level: u8,
    ctx: &mut TxContext,
) {
    assert!(_admin_cap.admin_level == ADMIN_LEVEL_SUPER, ENotAuthorized);
    assert!(admin_level <= ADMIN_LEVEL_MODERATOR, EInvalidAdminLevel);

    let new_admin_cap = PlatformAdminCap {
        id: object::new(ctx),
        admin_level,
    };

    transfer::transfer(new_admin_cap, recipient);
}

// === Verification Functions ===

/// Verify organizer has permission for an event
public fun verify_organizer(cap: &EventOrganizerCap, event_id: ID): bool {
    cap.event_id == event_id
}

/// Verify organizer can update event
public fun verify_can_update(cap: &EventOrganizerCap, event_id: ID): bool {
    cap.event_id == event_id && cap.permissions.can_update_event
}

/// Verify organizer can cancel event
public fun verify_can_cancel(cap: &EventOrganizerCap, event_id: ID): bool {
    cap.event_id == event_id && cap.permissions.can_cancel_event
}

/// Verify organizer can withdraw funds
public fun verify_can_withdraw(cap: &EventOrganizerCap, event_id: ID): bool {
    cap.event_id == event_id && cap.permissions.can_withdraw_funds
}

/// Verify validator has permission for an event
public fun verify_validator(cap: &ValidatorCap, event_id: ID): bool {
    cap.event_id == event_id
}

/// Verify admin capability level
public fun verify_admin_level(cap: &PlatformAdminCap, required_level: u8): bool {
    cap.admin_level <= required_level
}

// === Getter Functions ===

/// Get event ID from organizer cap
public fun get_organizer_event_id(cap: &EventOrganizerCap): ID {
    cap.event_id
}

/// Get event ID from validator cap
public fun get_validator_event_id(cap: &ValidatorCap): ID {
    cap.event_id
}

/// Get permissions from organizer cap
public fun get_organizer_permissions(cap: &EventOrganizerCap): OrganizerPermissions {
    cap.permissions
}

/// Get admin level
public fun get_admin_level(cap: &PlatformAdminCap): u8 {
    cap.admin_level
}

/// Get multi-sig organizers
public fun get_multisig_organizers(multisig: &MultiSigOrganizer): &vector<address> {
    &multisig.organizers
}

/// Get multi-sig approvals count
public fun get_multisig_approval_count(multisig: &MultiSigOrganizer): u64 {
    std::vector::length(&multisig.approvals)
}

/// Create custom permissions
public fun create_permissions(
    can_update_event: bool,
    can_cancel_event: bool,
    can_approve_registrations: bool,
    can_withdraw_funds: bool,
): OrganizerPermissions {
    OrganizerPermissions {
        can_update_event,
        can_cancel_event,
        can_approve_registrations,
        can_withdraw_funds,
    }
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ACCESS_CONTROL {}, ctx);
}

#[test_only]
public fun create_test_organizer_cap(event_id: ID, ctx: &mut TxContext): EventOrganizerCap {
    grant_organizer_cap(event_id, ctx)
}

#[test_only]
public fun create_test_validator_cap(
    event_id: ID,
    validator: address,
    ctx: &mut TxContext,
): ValidatorCap {
    ValidatorCap {
        id: object::new(ctx),
        event_id,
        validator_address: validator,
        granted_by: tx_context::sender(ctx),
    }
}
