/// Payments Module
/// Payment processing, refunds, and revenue management
module event_platform::payments;

use event_platform::access_control::{Self, EventOrganizerCap, PlatformAdminCap};
use std::string::String;
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::event;
use sui::object::{Self, UID, ID};
use sui::sui::SUI;
use sui::transfer;
use sui::tx_context::{Self, TxContext};

// === Error Codes ===
const ENotAuthorized: u64 = 1;
const EInsufficientPayment: u64 = 2;
const EInsufficientBalance: u64 = 3;
const EDiscountExpired: u64 = 4;
const EDiscountMaxUsed: u64 = 5;
const EInvalidDiscount: u64 = 6;
const ERefundNotAllowed: u64 = 7;
const EInvalidPaymentType: u64 = 8;

// === Constants ===
const PAYMENT_TYPE_TICKET: u8 = 0;
const PAYMENT_TYPE_REFUND: u8 = 1;
const PAYMENT_TYPE_FEE: u8 = 2;

const PAYMENT_STATUS_PENDING: u8 = 0;
const PAYMENT_STATUS_COMPLETED: u8 = 1;
const PAYMENT_STATUS_FAILED: u8 = 2;

// === One-Time-Witness ===
public struct PAYMENTS has drop {}

// === Main Structs ===

/// Payment record (stored for history)
public struct Payment has key, store {
    id: UID,
    payer: address,
    event_id: ID,
    amount: u64,
    payment_type: u8,
    timestamp: u64,
    status: u8,
}

/// Event treasury (holds funds per event)
public struct EventTreasury has key {
    id: UID,
    event_id: ID,
    organizer: address,
    balance: Balance<SUI>,
    platform_fee: u64,
    total_collected: u64,
    total_withdrawn: u64,
}

/// Platform treasury (shared)
public struct PlatformTreasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_fees_collected: u64,
    total_withdrawn: u64,
    admin: address,
}

/// Discount code
public struct DiscountCode has key, store {
    id: UID,
    code: String,
    event_id: ID,
    discount_percent: u64,
    max_uses: u64,
    current_uses: u64,
    expiry: u64,
}

/// Refund policy (nested)
public struct RefundPolicy has copy, drop, store {
    allows_refund: bool,
    refund_percent: u64,
    deadline_before_event: u64,
}

// === Event Logs ===

public struct PaymentProcessed has copy, drop {
    payment_id: ID,
    event_id: ID,
    payer: address,
    amount: u64,
    platform_fee: u64,
    timestamp: u64,
}

public struct RefundIssued has copy, drop {
    payment_id: ID,
    ticket_id: ID,
    recipient: address,
    refund_amount: u64,
    timestamp: u64,
}

public struct FundsWithdrawn has copy, drop {
    event_id: ID,
    organizer: address,
    amount: u64,
    timestamp: u64,
}

public struct PlatformFeesWithdrawn has copy, drop {
    admin: address,
    amount: u64,
    timestamp: u64,
}

public struct DiscountCodeCreated has copy, drop {
    code_id: ID,
    event_id: ID,
    discount_percent: u64,
    timestamp: u64,
}

public struct DiscountApplied has copy, drop {
    code_id: ID,
    user: address,
    original_price: u64,
    discounted_price: u64,
    timestamp: u64,
}

// === Init Function ===

/// Initialize platform treasury
fun init(_witness: PAYMENTS, ctx: &mut TxContext) {
    let platform_treasury = PlatformTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_fees_collected: 0,
        total_withdrawn: 0,
        admin: tx_context::sender(ctx),
    };
    transfer::share_object(platform_treasury);
}

// === Public Functions ===

/// Create event treasury for a new event
public fun create_event_treasury(
    event_id: ID,
    organizer: address,
    ctx: &mut TxContext,
): EventTreasury {
    EventTreasury {
        id: object::new(ctx),
        event_id,
        organizer,
        balance: balance::zero(),
        platform_fee: 0,
        total_collected: 0,
        total_withdrawn: 0,
    }
}

/// Process payment for ticket purchase
public fun process_payment(
    treasury: &mut EventTreasury,
    platform_treasury: &mut PlatformTreasury,
    payer: address,
    mut payment: Coin<SUI>,
    ticket_price: u64,
    platform_fee_percent: u64,
    ctx: &mut TxContext,
): Payment {
    let payment_amount = coin::value(&payment);
    assert!(payment_amount >= ticket_price, EInsufficientPayment);

    // Calculate platform fee
    let platform_fee = (ticket_price * platform_fee_percent) / 100;
    let organizer_amount = ticket_price - platform_fee;

    // Split payment
    let platform_fee_coin = coin::split(&mut payment, platform_fee, ctx);
    let organizer_coin = coin::split(&mut payment, organizer_amount, ctx);

    // Add to balances
    balance::join(&mut platform_treasury.balance, coin::into_balance(platform_fee_coin));
    balance::join(&mut treasury.balance, coin::into_balance(organizer_coin));

    // Handle excess payment (refund)
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, payer);
    } else {
        coin::destroy_zero(payment);
    };

    // Update stats
    treasury.total_collected = treasury.total_collected + ticket_price;
    treasury.platform_fee = treasury.platform_fee + platform_fee;
    platform_treasury.total_fees_collected = platform_treasury.total_fees_collected + platform_fee;

    // Create payment record
    let payment_uid = object::new(ctx);
    let payment_id = object::uid_to_inner(&payment_uid);
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    let payment_record = Payment {
        id: payment_uid,
        payer,
        event_id: treasury.event_id,
        amount: ticket_price,
        payment_type: PAYMENT_TYPE_TICKET,
        timestamp: current_time,
        status: PAYMENT_STATUS_COMPLETED,
    };

    event::emit(PaymentProcessed {
        payment_id,
        event_id: treasury.event_id,
        payer,
        amount: ticket_price,
        platform_fee,
        timestamp: current_time,
    });

    payment_record
}

/// Issue refund to user
public fun issue_refund(
    treasury: &mut EventTreasury,
    ticket_id: ID,
    recipient: address,
    refund_amount: u64,
    ctx: &mut TxContext,
): Payment {
    // Check if treasury has sufficient balance
    assert!(balance::value(&treasury.balance) >= refund_amount, EInsufficientBalance);

    // Take from balance and transfer to recipient
    let refund_coin = coin::take(&mut treasury.balance, refund_amount, ctx);
    transfer::public_transfer(refund_coin, recipient);

    // Create payment record
    let payment_uid = object::new(ctx);
    let payment_id = object::uid_to_inner(&payment_uid);
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    let payment_record = Payment {
        id: payment_uid,
        payer: recipient,
        event_id: treasury.event_id,
        amount: refund_amount,
        payment_type: PAYMENT_TYPE_REFUND,
        timestamp: current_time,
        status: PAYMENT_STATUS_COMPLETED,
    };

    event::emit(RefundIssued {
        payment_id,
        ticket_id,
        recipient,
        refund_amount,
        timestamp: current_time,
    });

    payment_record
}

/// Create discount code for an event
public fun create_discount_code(
    event_id: ID,
    code: String,
    discount_percent: u64,
    max_uses: u64,
    expiry: u64,
    cap: &EventOrganizerCap,
    ctx: &mut TxContext,
): DiscountCode {
    // Verify organizer owns this event
    assert!(access_control::verify_organizer(cap, event_id), ENotAuthorized);
    assert!(discount_percent <= 100, EInvalidDiscount);

    let code_uid = object::new(ctx);
    let code_id = object::uid_to_inner(&code_uid);

    let discount = DiscountCode {
        id: code_uid,
        code,
        event_id,
        discount_percent,
        max_uses,
        current_uses: 0,
        expiry,
    };

    event::emit(DiscountCodeCreated {
        code_id,
        event_id,
        discount_percent,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    discount
}

/// Apply discount code and calculate discounted price
public fun apply_discount(code: &mut DiscountCode, original_price: u64, ctx: &TxContext): u64 {
    let current_time = tx_context::epoch_timestamp_ms(ctx);

    // Check expiry
    assert!(current_time < code.expiry, EDiscountExpired);

    // Check max uses
    assert!(code.current_uses < code.max_uses, EDiscountMaxUsed);

    // Increment usage
    code.current_uses = code.current_uses + 1;

    // Calculate discounted price
    let discount_amount = (original_price * code.discount_percent) / 100;
    let discounted_price = original_price - discount_amount;

    event::emit(DiscountApplied {
        code_id: object::id(code),
        user: tx_context::sender(ctx),
        original_price,
        discounted_price,
        timestamp: current_time,
    });

    discounted_price
}

/// Organizer withdraws funds from event treasury
public fun withdraw_funds(
    treasury: &mut EventTreasury,
    cap: &EventOrganizerCap,
    ctx: &mut TxContext,
) {
    // Verify ownership and permission
    assert!(access_control::verify_can_withdraw(cap, treasury.event_id), ENotAuthorized);

    let amount = balance::value(&treasury.balance);
    if (amount > 0) {
        let withdrawn = coin::take(&mut treasury.balance, amount, ctx);
        transfer::public_transfer(withdrawn, treasury.organizer);

        treasury.total_withdrawn = treasury.total_withdrawn + amount;

        event::emit(FundsWithdrawn {
            event_id: treasury.event_id,
            organizer: treasury.organizer,
            amount,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    };
}

/// Admin withdraws platform fees
public fun withdraw_platform_fees(
    platform_treasury: &mut PlatformTreasury,
    _admin_cap: &PlatformAdminCap,
    ctx: &mut TxContext,
) {
    let amount = balance::value(&platform_treasury.balance);
    if (amount > 0) {
        let withdrawn = coin::take(&mut platform_treasury.balance, amount, ctx);
        transfer::public_transfer(withdrawn, platform_treasury.admin);

        platform_treasury.total_withdrawn = platform_treasury.total_withdrawn + amount;

        event::emit(PlatformFeesWithdrawn {
            admin: platform_treasury.admin,
            amount,
            timestamp: tx_context::epoch_timestamp_ms(ctx),
        });
    };
}

/// Calculate refund amount based on policy
public fun calculate_refund_amount(original_amount: u64, policy: &RefundPolicy): u64 {
    assert!(policy.allows_refund, ERefundNotAllowed);
    (original_amount * policy.refund_percent) / 100
}

// === View Functions ===

/// Get treasury balance
public fun get_treasury_balance(treasury: &EventTreasury): u64 {
    balance::value(&treasury.balance)
}

/// Get treasury stats
public fun get_treasury_stats(treasury: &EventTreasury): (u64, u64, u64, u64) {
    (
        balance::value(&treasury.balance),
        treasury.total_collected,
        treasury.total_withdrawn,
        treasury.platform_fee,
    )
}

/// Get platform treasury balance
public fun get_platform_balance(platform_treasury: &PlatformTreasury): u64 {
    balance::value(&platform_treasury.balance)
}

/// Get platform treasury stats
public fun get_platform_stats(platform_treasury: &PlatformTreasury): (u64, u64, u64) {
    (
        balance::value(&platform_treasury.balance),
        platform_treasury.total_fees_collected,
        platform_treasury.total_withdrawn,
    )
}

/// Get payment details
public fun get_payment_info(payment: &Payment): (address, ID, u64, u8, u64, u8) {
    (
        payment.payer,
        payment.event_id,
        payment.amount,
        payment.payment_type,
        payment.timestamp,
        payment.status,
    )
}

/// Get discount code info
public fun get_discount_info(code: &DiscountCode): (String, u64, u64, u64, u64) {
    (code.code, code.discount_percent, code.max_uses, code.current_uses, code.expiry)
}

/// Check if discount is valid
public fun is_discount_valid(code: &DiscountCode, ctx: &TxContext): bool {
    let current_time = tx_context::epoch_timestamp_ms(ctx);
    current_time < code.expiry && code.current_uses < code.max_uses
}

/// Create refund policy
public fun create_refund_policy(
    allows_refund: bool,
    refund_percent: u64,
    deadline_before_event: u64,
): RefundPolicy {
    RefundPolicy {
        allows_refund,
        refund_percent,
        deadline_before_event,
    }
}

/// Get event ID from treasury
public fun get_treasury_event_id(treasury: &EventTreasury): ID {
    treasury.event_id
}

// === Test Functions ===
#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(PAYMENTS {}, ctx);
}

#[test_only]
public fun create_test_treasury(
    event_id: ID,
    organizer: address,
    ctx: &mut TxContext,
): EventTreasury {
    create_event_treasury(event_id, organizer, ctx)
}
