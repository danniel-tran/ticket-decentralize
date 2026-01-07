/// Payments Module
/// Payment processing, treasury management, and revenue splitting
module event_platform::payments;

use std::string::String;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::event;

// ======== Error Codes ========
const EInsufficientPayment: u64 = 6000;
const EInsufficientBalance: u64 = 6001;
const ENotAuthorized: u64 = 6002;
const EInvalidDiscount: u64 = 6003;
const EDiscountExpired: u64 = 6004;
const EDiscountMaxUsed: u64 = 6005;
const EInvalidAmount: u64 = 6006;

// ======== Constants ========
const DEFAULT_PLATFORM_FEE_PERCENT: u64 = 250;  // 2.5%
const PERCENT_DENOMINATOR: u64 = 10000;

// ======== Structs ========

/// Event treasury for managing event funds
public struct EventTreasury has key {
    id: UID,
    event_id: ID,
    organizer: address,
    balance: Balance<SUI>,
    platform_fee: u64,
    total_collected: u64,
    total_withdrawn: u64,
    locked_for_refunds: u64,
}

/// Platform treasury for collecting fees (shared, no admin control)
public struct PlatformTreasury has key {
    id: UID,
    balance: Balance<SUI>,
    total_fees_collected: u64,
    total_withdrawn: u64,
}

/// Discount code for tickets
public struct DiscountCode has key, store {
    id: UID,
    code: String,
    event_id: ID,
    discount_percent: u64,
    max_uses: u64,
    current_uses: u64,
    expiry: u64,
}

// ======== Events ========

public struct PaymentProcessed has copy, drop {
    event_id: ID,
    payer: address,
    amount: u64,
    platform_fee: u64,
    organizer_amount: u64,
    timestamp: u64,
}

public struct RefundIssued has copy, drop {
    event_id: ID,
    recipient: address,
    ticket_id: ID,
    amount: u64,
    timestamp: u64,
}

public struct FundsWithdrawn has copy, drop {
    event_id: ID,
    organizer: address,
    amount: u64,
    timestamp: u64,
}

public struct DiscountApplied has copy, drop {
    event_id: ID,
    code: String,
    original_price: u64,
    discounted_price: u64,
    discount_percent: u64,
    timestamp: u64,
}

// ======== Init Function ========

fun init(ctx: &mut TxContext) {
    let platform_treasury = PlatformTreasury {
        id: object::new(ctx),
        balance: balance::zero(),
        total_fees_collected: 0,
        total_withdrawn: 0,
    };
    transfer::share_object(platform_treasury);
}

// ======== Public Functions ========

/// Create event treasury
public(package) fun create_event_treasury(
    event_id: ID,
    organizer: address,
    ctx: &mut TxContext,
): EventTreasury {
    EventTreasury {
        id: object::new(ctx),
        event_id,
        organizer,
        balance: balance::zero(),
        platform_fee: DEFAULT_PLATFORM_FEE_PERCENT,
        total_collected: 0,
        total_withdrawn: 0,
        locked_for_refunds: 0,
    }
}

/// Process payment and split between organizer and platform
public(package) fun process_payment(
    event_treasury: &mut EventTreasury,
    platform_treasury: &mut PlatformTreasury,
    payer: address,
    payment: Coin<SUI>,
    ticket_price: u64,
    platform_fee_percent: u64,
    ctx: &TxContext,
) {
    // Verify exact payment amount
    let payment_value = coin::value(&payment);
    assert!(payment_value == ticket_price, EInsufficientPayment);

    // Calculate split
    let platform_fee = (ticket_price * platform_fee_percent) / PERCENT_DENOMINATOR;
    let organizer_amount = ticket_price - platform_fee;

    // Convert coin to balance
    let mut payment_balance = coin::into_balance(payment);

    // Split balance
    let platform_balance = balance::split(&mut payment_balance, platform_fee);

    // Deposit to treasuries
    balance::join(&mut platform_treasury.balance, platform_balance);
    balance::join(&mut event_treasury.balance, payment_balance);

    // Update stats
    event_treasury.total_collected = event_treasury.total_collected + ticket_price;
    event_treasury.locked_for_refunds = event_treasury.locked_for_refunds + organizer_amount;

    platform_treasury.total_fees_collected = platform_treasury.total_fees_collected + platform_fee;

    event::emit(PaymentProcessed {
        event_id: event_treasury.event_id,
        payer,
        amount: ticket_price,
        platform_fee,
        organizer_amount,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Issue refund to ticket holder
public(package) fun issue_refund(
    treasury: &mut EventTreasury,
    ticket_id: ID,
    recipient: address,
    refund_amount: u64,
    ctx: &mut TxContext,
) {
    // Verify sufficient balance
    let current_balance = balance::value(&treasury.balance);
    assert!(current_balance >= refund_amount, EInsufficientBalance);

    // Take from balance and create coin
    let refund_balance = balance::split(&mut treasury.balance, refund_amount);
    let refund_coin = coin::from_balance(refund_balance, ctx);

    // Transfer to recipient
    transfer::public_transfer(refund_coin, recipient);

    // Update locked amount
    if (treasury.locked_for_refunds >= refund_amount) {
        treasury.locked_for_refunds = treasury.locked_for_refunds - refund_amount;
    };

    event::emit(RefundIssued {
        event_id: treasury.event_id,
        recipient,
        ticket_id,
        amount: refund_amount,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });
}

/// Withdraw funds from event treasury (organizer only)
public fun withdraw_funds(
    treasury: &mut EventTreasury,
    amount: u64,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == treasury.organizer, ENotAuthorized);

    // Calculate withdrawable (total - locked)
    let total = balance::value(&treasury.balance);
    let locked = treasury.locked_for_refunds;
    let withdrawable = if (total > locked) { total - locked } else { 0 };

    assert!(amount <= withdrawable, EInsufficientBalance);
    assert!(amount > 0, EInvalidAmount);

    // Withdraw
    let withdrawal_balance = balance::split(&mut treasury.balance, amount);
    let withdrawal_coin = coin::from_balance(withdrawal_balance, ctx);

    treasury.total_withdrawn = treasury.total_withdrawn + amount;

    event::emit(FundsWithdrawn {
        event_id: treasury.event_id,
        organizer: sender,
        amount,
        timestamp: tx_context::epoch_timestamp_ms(ctx),
    });

    transfer::public_transfer(withdrawal_coin, sender);
}

// Note: Platform fees accumulate in PlatformTreasury
// There is no withdrawal mechanism - fees stay in treasury permanently
// This ensures platform sustainability without centralized control

/// Create discount code
public fun create_discount_code(
    event_id: ID,
    code: String,
    discount_percent: u64,
    max_uses: u64,
    expiry: u64,
    ctx: &mut TxContext,
): DiscountCode {
    assert!(discount_percent <= 100, EInvalidDiscount);

    DiscountCode {
        id: object::new(ctx),
        code,
        event_id,
        discount_percent,
        max_uses,
        current_uses: 0,
        expiry,
    }
}

/// Apply discount code and return discounted price
public fun apply_discount(
    code: &mut DiscountCode,
    event_id: ID,
    original_price: u64,
    ctx: &TxContext,
): u64 {
    // Verify code is for correct event
    assert!(code.event_id == event_id, EInvalidDiscount);

    // Check expiry
    let now = tx_context::epoch_timestamp_ms(ctx);
    assert!(now < code.expiry, EDiscountExpired);

    // Check usage
    assert!(code.current_uses < code.max_uses, EDiscountMaxUsed);

    // Calculate discount
    let discount_amount = (original_price * code.discount_percent) / 100;
    let discounted_price = original_price - discount_amount;

    // Increment usage
    code.current_uses = code.current_uses + 1;

    event::emit(DiscountApplied {
        event_id,
        code: code.code,
        original_price,
        discounted_price,
        discount_percent: code.discount_percent,
        timestamp: now,
    });

    discounted_price
}

// ======== Package Functions ========

/// Add revenue to event treasury stats
public(package) fun add_revenue(treasury: &mut EventTreasury, amount: u64) {
    treasury.total_collected = treasury.total_collected + amount;
}

/// Lock amount for potential refunds
public(package) fun lock_for_refund(treasury: &mut EventTreasury, amount: u64) {
    treasury.locked_for_refunds = treasury.locked_for_refunds + amount;
}

/// Unlock refund amount (e.g., after refund deadline)
public(package) fun unlock_refund(treasury: &mut EventTreasury, amount: u64) {
    if (treasury.locked_for_refunds >= amount) {
        treasury.locked_for_refunds = treasury.locked_for_refunds - amount;
    };
}

// ======== Getter Functions ========

public fun get_treasury_balance(treasury: &EventTreasury): u64 {
    balance::value(&treasury.balance)
}

public fun get_withdrawable_amount(treasury: &EventTreasury): u64 {
    let total = balance::value(&treasury.balance);
    let locked = treasury.locked_for_refunds;
    if (total > locked) { total - locked } else { 0 }
}

public fun get_total_collected(treasury: &EventTreasury): u64 {
    treasury.total_collected
}

public fun get_total_withdrawn(treasury: &EventTreasury): u64 {
    treasury.total_withdrawn
}

public fun get_locked_for_refunds(treasury: &EventTreasury): u64 {
    treasury.locked_for_refunds
}

public fun get_platform_balance(treasury: &PlatformTreasury): u64 {
    balance::value(&treasury.balance)
}

public fun get_platform_fee_percent(treasury: &EventTreasury): u64 {
    treasury.platform_fee
}

public fun get_event_id(treasury: &EventTreasury): ID {
    treasury.event_id
}

public fun get_organizer(treasury: &EventTreasury): address {
    treasury.organizer
}

public fun get_discount_remaining_uses(code: &DiscountCode): u64 {
    if (code.max_uses > code.current_uses) {
        code.max_uses - code.current_uses
    } else {
        0
    }
}
