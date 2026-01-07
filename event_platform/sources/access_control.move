/// Access Control Module
/// Provides capability-based permission system for all platform operations
module event_platform::access_control;

use sui::event;

// ======== Error Codes ========
const EInvalidEventId: u64 = 1001;
const EInvalidPermission: u64 = 1003;

// ======== Constants ========
const ADMIN_LEVEL_SUPER_ADMIN: u8 = 0;
const ADMIN_LEVEL_MODERATOR: u8 = 1;

// ======== Structs ========
/// Organizer permissions configuration
public struct OrganizerPermissions has copy, drop, store {
    can_update_event: bool,
    can_cancel_event: bool,
    can_approve_registrations: bool,
    can_withdraw_funds: bool,
    can_grant_validators: bool,
}

/// Event organizer capability
public struct EventOrganizerCap has key, store {
    id: UID,
    event_id: ID,
    permissions: OrganizerPermissions,
    granted_at: u64,
}

/// Validator capability for checking in attendees
public struct ValidatorCap has key, store {
    id: UID,
    event_id: ID,
    validator_address: address,
    granted_by: address,
    granted_at: u64,
}

// ======== Events ========

public struct OrganizerCapCreated has copy, drop {
    cap_id: ID,
    event_id: ID,
    organizer: address,
    timestamp: u64,
}

public struct LimitedCapCreated has copy, drop {
    cap_id: ID,
    event_id: ID,
    delegated_to: address,
    timestamp: u64,
}

public struct ValidatorCapGranted has copy, drop {
    cap_id: ID,
    event_id: ID,
    validator: address,
    granted_by: address,
    timestamp: u64,
}

// ======== Factory Functions ========

/// Create full organizer capability (called by events module)
public(package) fun create_organizer_cap(
    event_id: ID,
    ctx: &mut TxContext,
): EventOrganizerCap {
    let cap_id = object::new(ctx);
    let organizer = tx_context::sender(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(OrganizerCapCreated {
        cap_id: object::uid_to_inner(&cap_id),
        event_id,
        organizer,
        timestamp,
    });

    EventOrganizerCap {
        id: cap_id,
        event_id,
        permissions: full_permissions(),
        granted_at: timestamp,
    }
}

/// Create limited organizer capability for delegation
public fun create_limited_cap(
    original_cap: &EventOrganizerCap,
    permissions: OrganizerPermissions,
    ctx: &mut TxContext,
): EventOrganizerCap {
    // Verify original cap is valid
    verify_organizer(original_cap, original_cap.event_id, ctx);

    let cap_id = object::new(ctx);
    let delegated_to = tx_context::sender(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(LimitedCapCreated {
        cap_id: object::uid_to_inner(&cap_id),
        event_id: original_cap.event_id,
        delegated_to,
        timestamp,
    });

    EventOrganizerCap {
        id: cap_id,
        event_id: original_cap.event_id,
        permissions,
        granted_at: timestamp,
    }
}

/// Grant validator capability
public fun grant_validator_cap(
    event_id: ID,
    validator: address,
    organizer_cap: &EventOrganizerCap,
    ctx: &mut TxContext,
): ValidatorCap {
    // Verify organizer has permission to grant validators
    verify_organizer(organizer_cap, event_id, ctx);
    assert!(organizer_cap.permissions.can_grant_validators, EInvalidPermission);

    let cap_id = object::new(ctx);
    let granted_by = tx_context::sender(ctx);
    let timestamp = tx_context::epoch_timestamp_ms(ctx);

    event::emit(ValidatorCapGranted {
        cap_id: object::uid_to_inner(&cap_id),
        event_id,
        validator,
        granted_by,
        timestamp,
    });

    ValidatorCap {
        id: cap_id,
        event_id,
        validator_address: validator,
        granted_by,
        granted_at: timestamp,
    }
}

// ======== Verification Functions ========

/// Verify organizer capability
public fun verify_organizer(cap: &EventOrganizerCap, event_id: ID, _ctx: &TxContext) {
    assert!(cap.event_id == event_id, EInvalidEventId);
}

/// Verify can update event
public fun verify_can_update(cap: &EventOrganizerCap, event_id: ID, ctx: &TxContext) {
    verify_organizer(cap, event_id, ctx);
    assert!(cap.permissions.can_update_event, EInvalidPermission);
}

/// Verify can cancel event
public fun verify_can_cancel(cap: &EventOrganizerCap, event_id: ID, ctx: &TxContext) {
    verify_organizer(cap, event_id, ctx);
    assert!(cap.permissions.can_cancel_event, EInvalidPermission);
}

/// Verify can approve registrations
public fun verify_can_approve(cap: &EventOrganizerCap, event_id: ID, ctx: &TxContext) {
    verify_organizer(cap, event_id, ctx);
    assert!(cap.permissions.can_approve_registrations, EInvalidPermission);
}

/// Verify can withdraw funds
public fun verify_can_withdraw(cap: &EventOrganizerCap, event_id: ID, ctx: &TxContext) {
    verify_organizer(cap, event_id, ctx);
    assert!(cap.permissions.can_withdraw_funds, EInvalidPermission);
}

/// Verify validator capability
public fun verify_validator(cap: &ValidatorCap, event_id: ID, _ctx: &TxContext) {
    assert!(cap.event_id == event_id, EInvalidEventId);
}

// ======== Helper Functions ========

/// Create full permissions (all true)
fun full_permissions(): OrganizerPermissions {
    OrganizerPermissions {
        can_update_event: true,
        can_cancel_event: true,
        can_approve_registrations: true,
        can_withdraw_funds: true,
        can_grant_validators: true,
    }
}

// ======== Getter Functions ========

public fun get_event_id(cap: &EventOrganizerCap): ID {
    cap.event_id
}

public fun get_validator_event_id(cap: &ValidatorCap): ID {
    cap.event_id
}

public fun get_validator_address(cap: &ValidatorCap): address {
    cap.validator_address
}

public fun has_update_permission(cap: &EventOrganizerCap): bool {
    cap.permissions.can_update_event
}

public fun has_cancel_permission(cap: &EventOrganizerCap): bool {
    cap.permissions.can_cancel_event
}

public fun has_withdraw_permission(cap: &EventOrganizerCap): bool {
    cap.permissions.can_withdraw_funds
}
