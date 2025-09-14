;; Instant Payout Processor Contract
;; Automated insurance payouts based on flight status triggers
;; Handles policy lifecycle and claims processing

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-POLICY-INACTIVE (err u202))
(define-constant ERR-INSUFFICIENT-FUNDS (err u203))
(define-constant ERR-POLICY-EXISTS (err u204))
(define-constant ERR-INVALID-AMOUNT (err u205))
(define-constant ERR-CLAIM-NOT-ELIGIBLE (err u206))
(define-constant ERR-ALREADY-CLAIMED (err u207))
(define-constant ERR-POLICY-EXPIRED (err u208))
(define-constant ERR-INVALID-FLIGHT (err u209))
(define-constant ERR-TRANSFER-FAILED (err u210))

;; Flight status constants (must match oracle contract)
(define-constant STATUS-UNKNOWN u0)
(define-constant STATUS-ON-TIME u1)
(define-constant STATUS-DELAYED u2)
(define-constant STATUS-CANCELLED u3)

;; Policy status constants
(define-constant POLICY-ACTIVE u1)
(define-constant POLICY-CLAIMED u2)
(define-constant POLICY-EXPIRED u3)
(define-constant POLICY-CANCELLED u4)

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-policy-id uint u1)
(define-data-var total-premiums uint u0)
(define-data-var total-payouts uint u0)
(define-data-var contract-balance uint u0)

;; Flight data structure (local copy for policy reference)
(define-map flight-info
  { flight-id: uint }
  {
    airline: (buff 8),
    flight-number: uint,
    departure-date: uint,
    registered: bool
  }
)

;; Policy data structure
(define-map policies
  { policy-id: uint }
  {
    holder: principal,
    flight-id: uint,
    premium: uint,
    coverage-amount: uint,
    purchase-block: uint,
    expiry-block: uint,
    status: uint,
    claim-block: (optional uint),
    payout-amount: (optional uint)
  }
)

;; Policy lookup by holder and flight
(define-map holder-flight-policies
  { holder: principal, flight-id: uint }
  { policy-ids: (list 10 uint) }
)

;; Holder policies index
(define-map holder-policies
  { holder: principal }
  { policy-ids: (list 50 uint), total-policies: uint }
)

;; Contract statistics
(define-map daily-stats
  { date: uint }
  {
    policies-created: uint,
    total-premium: uint,
    claims-processed: uint,
    total-payouts: uint
  }
)

;; Public functions

;; Register flight for insurance (simplified oracle integration)
(define-public (register-flight-for-insurance (flight-id uint) (airline (buff 8)) (flight-number uint) (departure-date uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (> flight-number u0) ERR-INVALID-FLIGHT)
    (asserts! (is-none (map-get? flight-info { flight-id: flight-id })) ERR-POLICY-EXISTS)
    
    (map-set flight-info
      { flight-id: flight-id }
      {
        airline: airline,
        flight-number: flight-number,
        departure-date: departure-date,
        registered: true
      }
    )
    
    (ok true)
  )
)

;; Purchase insurance policy
(define-public (purchase-policy (flight-id uint) (coverage-amount uint) (premium uint) (expiry-blocks uint))
  (let
    (
      (policy-id (var-get next-policy-id))
      (flight-data (unwrap! (map-get? flight-info { flight-id: flight-id }) ERR-INVALID-FLIGHT))
      (expiry-block (+ stacks-block-height expiry-blocks))
      (today (get-today-date))
    )
    (asserts! (> premium u0) ERR-INVALID-AMOUNT)
    (asserts! (> coverage-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> expiry-blocks u0) ERR-INVALID-AMOUNT)
    (asserts! (get registered flight-data) ERR-INVALID-FLIGHT)
    
    ;; Create policy
    (map-set policies
      { policy-id: policy-id }
      {
        holder: tx-sender,
        flight-id: flight-id,
        premium: premium,
        coverage-amount: coverage-amount,
        purchase-block: stacks-block-height,
        expiry-block: expiry-block,
        status: POLICY-ACTIVE,
        claim-block: none,
        payout-amount: none
      }
    )
    
    ;; Update holder policies
    (update-holder-policies tx-sender policy-id)
    
    ;; Update holder-flight mapping
    (update-holder-flight-policies tx-sender flight-id policy-id)
    
    ;; Update financial tracking
    (var-set total-premiums (+ (var-get total-premiums) premium))
    (var-set contract-balance (+ (var-get contract-balance) premium))
    
    ;; Update daily stats
    (update-daily-stats today premium u0 u0)
    
    ;; Increment policy ID
    (var-set next-policy-id (+ policy-id u1))
    
    (ok policy-id)
  )
)

;; Claim payout (check flight status and process)
(define-public (claim-payout (policy-id uint) (flight-status uint))
  (let
    (
      (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR-NOT-FOUND))
      (is-eligible (is-claim-eligible flight-status))
      (payout-amount (get coverage-amount policy-data))
      (today (get-today-date))
    )
    (asserts! (is-eq tx-sender (get holder policy-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status policy-data) POLICY-ACTIVE) ERR-POLICY-INACTIVE)
    (asserts! (< stacks-block-height (get expiry-block policy-data)) ERR-POLICY-EXPIRED)
    (asserts! is-eligible ERR-CLAIM-NOT-ELIGIBLE)
    (asserts! (>= (var-get contract-balance) payout-amount) ERR-INSUFFICIENT-FUNDS)
    
    ;; Update policy status
    (map-set policies
      { policy-id: policy-id }
      (merge policy-data
        {
          status: POLICY-CLAIMED,
          claim-block: (some stacks-block-height),
          payout-amount: (some payout-amount)
        }
      )
    )
    
    ;; Process payout (simulated transfer)
    (var-set contract-balance (- (var-get contract-balance) payout-amount))
    (var-set total-payouts (+ (var-get total-payouts) payout-amount))
    
    ;; Update daily stats
    (update-daily-stats today u0 u1 payout-amount)
    
    (ok payout-amount)
  )
)

;; Cancel policy (before expiry, owner only)
(define-public (cancel-policy (policy-id uint))
  (let
    (
      (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR-NOT-FOUND))
      (refund-amount (/ (get premium policy-data) u2)) ;; 50% refund
    )
    (asserts! (is-eq tx-sender (get holder policy-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status policy-data) POLICY-ACTIVE) ERR-POLICY-INACTIVE)
    (asserts! (< stacks-block-height (get expiry-block policy-data)) ERR-POLICY-EXPIRED)
    
    ;; Update policy status
    (map-set policies
      { policy-id: policy-id }
      (merge policy-data
        {
          status: POLICY-CANCELLED,
          claim-block: (some stacks-block-height),
          payout-amount: (some refund-amount)
        }
      )
    )
    
    ;; Process refund (simulated transfer)
    (var-set contract-balance (- (var-get contract-balance) refund-amount))
    
    (ok refund-amount)
  )
)

;; Admin function to expire old policies
(define-public (expire-policy (policy-id uint))
  (let
    (
      (policy-data (unwrap! (map-get? policies { policy-id: policy-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status policy-data) POLICY-ACTIVE) ERR-POLICY-INACTIVE)
    (asserts! (>= stacks-block-height (get expiry-block policy-data)) ERR-POLICY-EXPIRED)
    
    ;; Update policy status
    (map-set policies
      { policy-id: policy-id }
      (merge policy-data { status: POLICY-EXPIRED })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get policy data
(define-read-only (get-policy-data (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

;; Get flight info
(define-read-only (get-flight-info (flight-id uint))
  (map-get? flight-info { flight-id: flight-id })
)

;; Get holder policies
(define-read-only (get-holder-policies (holder principal))
  (map-get? holder-policies { holder: holder })
)

;; Get policies for holder and flight
(define-read-only (get-holder-flight-policies (holder principal) (flight-id uint))
  (map-get? holder-flight-policies { holder: holder, flight-id: flight-id })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-policies: (- (var-get next-policy-id) u1),
    total-premiums: (var-get total-premiums),
    total-payouts: (var-get total-payouts),
    contract-balance: (var-get contract-balance),
    contract-owner: (var-get contract-owner)
  }
)

;; Get daily statistics
(define-read-only (get-daily-stats (date uint))
  (map-get? daily-stats { date: date })
)

;; Check if policy is active
(define-read-only (is-policy-active (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy-data 
      (and (is-eq (get status policy-data) POLICY-ACTIVE)
           (< stacks-block-height (get expiry-block policy-data)))
    false
  )
)

;; Private functions

;; Check if claim is eligible based on flight status
(define-private (is-claim-eligible (flight-status uint))
  (or (is-eq flight-status STATUS-DELAYED)
      (is-eq flight-status STATUS-CANCELLED))
)

;; Update holder policies list
(define-private (update-holder-policies (holder principal) (policy-id uint))
  (match (map-get? holder-policies { holder: holder })
    existing-data
      (map-set holder-policies
        { holder: holder }
        {
          policy-ids: (unwrap-panic (as-max-len? (append (get policy-ids existing-data) policy-id) u50)),
          total-policies: (+ (get total-policies existing-data) u1)
        }
      )
    ;; First policy for this holder
    (map-set holder-policies
      { holder: holder }
      {
        policy-ids: (list policy-id),
        total-policies: u1
      }
    )
  )
)

;; Update holder-flight policies mapping
(define-private (update-holder-flight-policies (holder principal) (flight-id uint) (policy-id uint))
  (match (map-get? holder-flight-policies { holder: holder, flight-id: flight-id })
    existing-data
      (map-set holder-flight-policies
        { holder: holder, flight-id: flight-id }
        {
          policy-ids: (unwrap-panic (as-max-len? (append (get policy-ids existing-data) policy-id) u10))
        }
      )
    ;; First policy for this holder-flight combination
    (map-set holder-flight-policies
      { holder: holder, flight-id: flight-id }
      { policy-ids: (list policy-id) }
    )
  )
)

;; Update daily statistics
(define-private (update-daily-stats (date uint) (premium uint) (claims uint) (payouts uint))
  (match (map-get? daily-stats { date: date })
    existing-stats
      (map-set daily-stats
        { date: date }
        {
          policies-created: (+ (get policies-created existing-stats) (if (> premium u0) u1 u0)),
          total-premium: (+ (get total-premium existing-stats) premium),
          claims-processed: (+ (get claims-processed existing-stats) claims),
          total-payouts: (+ (get total-payouts existing-stats) payouts)
        }
      )
    ;; First entry for this date
    (map-set daily-stats
      { date: date }
      {
        policies-created: (if (> premium u0) u1 u0),
        total-premium: premium,
        claims-processed: claims,
        total-payouts: payouts
      }
    )
  )
)

;; Get today's date (simplified as block height / 144 for ~daily blocks)
(define-private (get-today-date)
  (/ stacks-block-height u144)
)


