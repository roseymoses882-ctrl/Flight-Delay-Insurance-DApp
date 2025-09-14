;; Flight Data Oracle Contract
;; Integration with flight tracking APIs for real-time delay and cancellation data
;; Provides tamper-evident flight status recording with whitelisted reporters

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-STATUS (err u102))
(define-constant ERR-FLIGHT-EXISTS (err u103))
(define-constant ERR-INVALID-DATE (err u104))
(define-constant ERR-INVALID-FLIGHT-NUMBER (err u105))
(define-constant ERR-REPORTER-EXISTS (err u106))
(define-constant ERR-REPORTER-NOT-FOUND (err u107))

;; Flight status constants
(define-constant STATUS-UNKNOWN u0)
(define-constant STATUS-ON-TIME u1)
(define-constant STATUS-DELAYED u2)
(define-constant STATUS-CANCELLED u3)

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-flight-id uint u1)
(define-data-var reporter-count uint u0)

;; Flight data structure
(define-map flights
  { flight-id: uint }
  {
    airline: (buff 8),
    flight-number: uint,
    departure-date: uint, ;; YYYYMMDD format
    status: uint,
    last-updated: uint,
    reporter: principal
  }
)

;; Flight lookup by airline/number/date
(define-map flight-lookup
  { airline: (buff 8), flight-number: uint, departure-date: uint }
  { flight-id: uint }
)

;; Reporter whitelist
(define-map authorized-reporters
  { reporter: principal }
  { active: bool, reports-count: uint }
)

;; Flight status history for audit trail
(define-map status-history
  { flight-id: uint, sequence: uint }
  {
    status: uint,
    timestamp: uint,
    reporter: principal,
    block-height: uint
  }
)

;; Track history sequence per flight
(define-map flight-history-sequence
  { flight-id: uint }
  { next-sequence: uint }
)

;; Public functions

;; Add a new authorized reporter (owner only)
(define-public (add-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (is-none (map-get? authorized-reporters { reporter: reporter })) ERR-REPORTER-EXISTS)
    (map-set authorized-reporters 
      { reporter: reporter }
      { active: true, reports-count: u0 }
    )
    (var-set reporter-count (+ (var-get reporter-count) u1))
    (ok true)
  )
)

;; Remove an authorized reporter (owner only)
(define-public (remove-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? authorized-reporters { reporter: reporter })) ERR-REPORTER-NOT-FOUND)
    (map-set authorized-reporters
      { reporter: reporter }
      { active: false, reports-count: u0 }
    )
    (var-set reporter-count (- (var-get reporter-count) u1))
    (ok true)
  )
)

;; Register a new flight (authorized reporters only)
(define-public (register-flight (airline (buff 8)) (flight-number uint) (departure-date uint))
  (let
    (
      (flight-id (var-get next-flight-id))
      (lookup-key { airline: airline, flight-number: flight-number, departure-date: departure-date })
    )
    (asserts! (is-reporter-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> flight-number u0) ERR-INVALID-FLIGHT-NUMBER)
    (asserts! (is-valid-date departure-date) ERR-INVALID-DATE)
    (asserts! (is-none (map-get? flight-lookup lookup-key)) ERR-FLIGHT-EXISTS)
    
    ;; Create flight record
    (map-set flights
      { flight-id: flight-id }
      {
        airline: airline,
        flight-number: flight-number,
        departure-date: departure-date,
        status: STATUS-UNKNOWN,
        last-updated: stacks-block-height,
        reporter: tx-sender
      }
    )
    
    ;; Create lookup entry
    (map-set flight-lookup lookup-key { flight-id: flight-id })
    
    ;; Initialize history sequence
    (map-set flight-history-sequence { flight-id: flight-id } { next-sequence: u1 })
    
    ;; Add initial status to history
    (map-set status-history
      { flight-id: flight-id, sequence: u0 }
      {
        status: STATUS-UNKNOWN,
        timestamp: stacks-block-height,
        reporter: tx-sender,
        block-height: stacks-block-height
      }
    )
    
    ;; Update reporter count
    (increment-reporter-count tx-sender)
    
    ;; Increment flight ID
    (var-set next-flight-id (+ flight-id u1))
    
    (ok flight-id)
  )
)

;; Update flight status (authorized reporters only)
(define-public (update-flight-status (flight-id uint) (new-status uint))
  (let
    (
      (flight-data (unwrap! (map-get? flights { flight-id: flight-id }) ERR-NOT-FOUND))
      (history-seq (unwrap! (map-get? flight-history-sequence { flight-id: flight-id }) ERR-NOT-FOUND))
      (next-seq (get next-sequence history-seq))
    )
    (asserts! (is-reporter-authorized tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    
    ;; Update flight record
    (map-set flights
      { flight-id: flight-id }
      (merge flight-data
        {
          status: new-status,
          last-updated: stacks-block-height,
          reporter: tx-sender
        }
      )
    )
    
    ;; Add to status history
    (map-set status-history
      { flight-id: flight-id, sequence: next-seq }
      {
        status: new-status,
        timestamp: stacks-block-height,
        reporter: tx-sender,
        block-height: stacks-block-height
      }
    )
    
    ;; Update sequence counter
    (map-set flight-history-sequence
      { flight-id: flight-id }
      { next-sequence: (+ next-seq u1) }
    )
    
    ;; Update reporter count
    (increment-reporter-count tx-sender)
    
    (ok true)
  )
)

;; Read-only functions

;; Get flight data by ID
(define-read-only (get-flight-data (flight-id uint))
  (map-get? flights { flight-id: flight-id })
)

;; Get flight ID by airline/number/date
(define-read-only (get-flight-id (airline (buff 8)) (flight-number uint) (departure-date uint))
  (map-get? flight-lookup { airline: airline, flight-number: flight-number, departure-date: departure-date })
)

;; Get flight status
(define-read-only (get-flight-status (flight-id uint))
  (match (map-get? flights { flight-id: flight-id })
    flight-data (some (get status flight-data))
    none
  )
)

;; Get status history for a flight
(define-read-only (get-status-history (flight-id uint) (sequence uint))
  (map-get? status-history { flight-id: flight-id, sequence: sequence })
)

;; Get reporter info
(define-read-only (get-reporter-info (reporter principal))
  (map-get? authorized-reporters { reporter: reporter })
)

;; Check if reporter is authorized
(define-read-only (is-reporter-authorized (reporter principal))
  (match (map-get? authorized-reporters { reporter: reporter })
    reporter-info (get active reporter-info)
    false
  )
)

;; Get contract stats
(define-read-only (get-contract-stats)
  {
    total-flights: (- (var-get next-flight-id) u1),
    authorized-reporters: (var-get reporter-count),
    contract-owner: (var-get contract-owner)
  }
)

;; Private functions

;; Validate flight status value
(define-private (is-valid-status (status uint))
  (or (is-eq status STATUS-UNKNOWN)
      (is-eq status STATUS-ON-TIME)
      (is-eq status STATUS-DELAYED)
      (is-eq status STATUS-CANCELLED))
)

;; Validate date format (basic YYYYMMDD validation)
(define-private (is-valid-date (date uint))
  (and (>= date u20200101) (<= date u20991231))
)

;; Increment reporter's report count
(define-private (increment-reporter-count (reporter principal))
  (match (map-get? authorized-reporters { reporter: reporter })
    reporter-info
      (map-set authorized-reporters
        { reporter: reporter }
        (merge reporter-info { reports-count: (+ (get reports-count reporter-info) u1) })
      )
    false
  )
)

;; Initialize contract with owner as first reporter
(begin
  (map-set authorized-reporters
    { reporter: tx-sender }
    { active: true, reports-count: u0 }
  )
  (var-set reporter-count u1)
)

