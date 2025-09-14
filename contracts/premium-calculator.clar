;; Premium Calculator Contract
;; Dynamic premium pricing based on historical flight performance data
;; Provides deterministic premium quotes using risk assessment algorithms

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u300))
(define-constant ERR-INVALID-RISK-SCORE (err u301))
(define-constant ERR-INVALID-COVERAGE (err u302))
(define-constant ERR-INVALID-DURATION (err u303))
(define-constant ERR-ROUTE-NOT-FOUND (err u304))
(define-constant ERR-AIRLINE-NOT-FOUND (err u305))
(define-constant ERR-INVALID-BASE-RATE (err u306))
(define-constant ERR-CALCULATION-OVERFLOW (err u307))
(define-constant ERR-INVALID-MULTIPLIER (err u308))
(define-constant ERR-ROUTE-EXISTS (err u309))

;; Risk level constants
(define-constant RISK-VERY-LOW u1)
(define-constant RISK-LOW u2)
(define-constant RISK-MEDIUM u3)
(define-constant RISK-HIGH u4)
(define-constant RISK-VERY-HIGH u5)

;; Base pricing constants (in basis points, 10000 = 100%)
(define-constant BASE-PREMIUM-RATE u500)  ;; 5% base rate
(define-constant MIN-PREMIUM u100)        ;; Minimum premium amount
(define-constant MAX-PREMIUM u100000)     ;; Maximum premium amount
(define-constant PRECISION u10000)        ;; Calculation precision

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-quotes uint u0)
(define-data-var base-rate uint BASE-PREMIUM-RATE)
(define-data-var seasonal-multiplier uint u10000) ;; 100% = no adjustment

;; Airline risk profiles
(define-map airline-risk-data
  { airline: (buff 8) }
  {
    delay-rate: uint,          ;; Historical delay rate in basis points
    cancellation-rate: uint,   ;; Historical cancellation rate in basis points
    reliability-score: uint,   ;; Overall reliability (1-100)
    total-flights: uint,       ;; Total flights in dataset
    risk-multiplier: uint      ;; Risk adjustment multiplier (10000 = 100%)
  }
)

;; Route-specific risk data
(define-map route-risk-data
  { origin: (buff 8), destination: (buff 8) }
  {
    weather-risk: uint,        ;; Weather-related delay risk
    congestion-risk: uint,     ;; Airport congestion risk
    distance-factor: uint,     ;; Distance-based risk factor
    seasonal-variance: uint,   ;; Seasonal risk variance
    route-multiplier: uint     ;; Route-specific multiplier
  }
)

;; Flight-specific historical data
(define-map flight-history
  { airline: (buff 8), flight-number: uint }
  {
    on-time-rate: uint,        ;; Historical on-time performance
    avg-delay-minutes: uint,   ;; Average delay in minutes
    sample-size: uint,         ;; Number of historical records
    last-updated: uint,        ;; Block height of last update
    performance-score: uint    ;; Calculated performance score (1-100)
  }
)

;; Premium calculation cache
(define-map premium-cache
  { 
    airline: (buff 8), 
    flight-number: uint, 
    coverage: uint, 
    duration: uint, 
    risk-hash: uint 
  }
  {
    premium: uint,
    calculated-at: uint,
    risk-score: uint,
    base-rate-used: uint
  }
)

;; Quote history for analytics
(define-map quote-requests
  { quote-id: uint }
  {
    requester: principal,
    airline: (buff 8),
    flight-number: uint,
    coverage-amount: uint,
    duration-days: uint,
    calculated-premium: uint,
    risk-assessment: uint,
    timestamp: uint
  }
)

;; Public functions

;; Add or update airline risk data (owner only)
(define-public (update-airline-risk (airline (buff 8)) (delay-rate uint) (cancellation-rate uint) (reliability-score uint) (total-flights uint))
  (let
    (
      (risk-multiplier (calculate-airline-multiplier delay-rate cancellation-rate reliability-score))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (<= delay-rate u10000) ERR-INVALID-RISK-SCORE)
    (asserts! (<= cancellation-rate u10000) ERR-INVALID-RISK-SCORE)
    (asserts! (and (> reliability-score u0) (<= reliability-score u100)) ERR-INVALID-RISK-SCORE)
    
    (map-set airline-risk-data
      { airline: airline }
      {
        delay-rate: delay-rate,
        cancellation-rate: cancellation-rate,
        reliability-score: reliability-score,
        total-flights: total-flights,
        risk-multiplier: risk-multiplier
      }
    )
    
    (ok true)
  )
)

;; Add or update route risk data (owner only)
(define-public (update-route-risk (origin (buff 8)) (destination (buff 8)) (weather-risk uint) (congestion-risk uint) (distance-factor uint))
  (let
    (
      (route-multiplier (calculate-route-multiplier weather-risk congestion-risk distance-factor))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (<= weather-risk u100) ERR-INVALID-RISK-SCORE)
    (asserts! (<= congestion-risk u100) ERR-INVALID-RISK-SCORE)
    (asserts! (> distance-factor u0) ERR-INVALID-RISK-SCORE)
    
    (map-set route-risk-data
      { origin: origin, destination: destination }
      {
        weather-risk: weather-risk,
        congestion-risk: congestion-risk,
        distance-factor: distance-factor,
        seasonal-variance: u10000, ;; Default no variance
        route-multiplier: route-multiplier
      }
    )
    
    (ok true)
  )
)

;; Update flight-specific historical performance (owner only)
(define-public (update-flight-history (airline (buff 8)) (flight-number uint) (on-time-rate uint) (avg-delay-minutes uint) (sample-size uint))
  (let
    (
      (performance-score (calculate-performance-score on-time-rate avg-delay-minutes))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (<= on-time-rate u10000) ERR-INVALID-RISK-SCORE)
    (asserts! (> sample-size u0) ERR-INVALID-RISK-SCORE)
    
    (map-set flight-history
      { airline: airline, flight-number: flight-number }
      {
        on-time-rate: on-time-rate,
        avg-delay-minutes: avg-delay-minutes,
        sample-size: sample-size,
        last-updated: stacks-block-height,
        performance-score: performance-score
      }
    )
    
    (ok true)
  )
)

;; Calculate premium quote
(define-public (calculate-premium (airline (buff 8)) (flight-number uint) (coverage-amount uint) (duration-days uint) (origin (buff 8)) (destination (buff 8)))
  (let
    (
      (quote-id (var-get total-quotes))
      (risk-hash (calculate-risk-hash airline flight-number origin destination))
      (cached-result (map-get? premium-cache 
        { airline: airline, flight-number: flight-number, coverage: coverage-amount, duration: duration-days, risk-hash: risk-hash }))
    )
    (asserts! (> coverage-amount u0) ERR-INVALID-COVERAGE)
    (asserts! (and (> duration-days u0) (<= duration-days u365)) ERR-INVALID-DURATION)
    
    ;; Check cache first
    (match cached-result
      cached-data
        ;; Use cached result if less than 144 blocks old (~24 hours)
        (if (< (- stacks-block-height (get calculated-at cached-data)) u144)
          (begin
            (record-quote-request quote-id tx-sender airline flight-number coverage-amount duration-days 
                                  (get premium cached-data) (get risk-score cached-data))
            (ok (get premium cached-data))
          )
          ;; Recalculate if cache is stale
          (calculate-fresh-premium quote-id airline flight-number coverage-amount duration-days origin destination risk-hash)
        )
      ;; No cached result, calculate fresh
      (calculate-fresh-premium quote-id airline flight-number coverage-amount duration-days origin destination risk-hash)
    )
  )
)

;; Update base rate (owner only)
(define-public (update-base-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (and (> new-rate u0) (<= new-rate u5000)) ERR-INVALID-BASE-RATE) ;; Max 50%
    (var-set base-rate new-rate)
    (ok true)
  )
)

;; Update seasonal multiplier (owner only)
(define-public (update-seasonal-multiplier (new-multiplier uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-UNAUTHORIZED)
    (asserts! (and (>= new-multiplier u5000) (<= new-multiplier u20000)) ERR-INVALID-MULTIPLIER) ;; 50% to 200%
    (var-set seasonal-multiplier new-multiplier)
    (ok true)
  )
)

;; Read-only functions

;; Get airline risk data
(define-read-only (get-airline-risk (airline (buff 8)))
  (map-get? airline-risk-data { airline: airline })
)

;; Get route risk data
(define-read-only (get-route-risk (origin (buff 8)) (destination (buff 8)))
  (map-get? route-risk-data { origin: origin, destination: destination })
)

;; Get flight history
(define-read-only (get-flight-history (airline (buff 8)) (flight-number uint))
  (map-get? flight-history { airline: airline, flight-number: flight-number })
)

;; Get quote request details
(define-read-only (get-quote-request (quote-id uint))
  (map-get? quote-requests { quote-id: quote-id })
)

;; Get contract statistics
(define-read-only (get-calculator-stats)
  {
    total-quotes: (var-get total-quotes),
    base-rate: (var-get base-rate),
    seasonal-multiplier: (var-get seasonal-multiplier),
    contract-owner: (var-get contract-owner)
  }
)

;; Get quick risk assessment
(define-read-only (get-risk-assessment (airline (buff 8)) (flight-number uint) (origin (buff 8)) (destination (buff 8)))
  (let
    (
      (airline-risk (get-airline-risk airline))
      (route-risk (get-route-risk origin destination))
      (flight-perf (get-flight-history airline flight-number))
    )
    {
      airline-risk-level: (if (is-some airline-risk) (assess-airline-risk-level (unwrap-panic airline-risk)) u0),
      route-risk-level: (if (is-some route-risk) (assess-route-risk-level (unwrap-panic route-risk)) u0),
      flight-performance: (if (is-some flight-perf) (get performance-score (unwrap-panic flight-perf)) u0),
      overall-risk: (calculate-composite-risk airline-risk route-risk flight-perf)
    }
  )
)

;; Private functions

;; Calculate fresh premium (internal)
(define-private (calculate-fresh-premium (quote-id uint) (airline (buff 8)) (flight-number uint) (coverage-amount uint) (duration-days uint) (origin (buff 8)) (destination (buff 8)) (risk-hash uint))
  (let
    (
      (airline-risk (get-airline-risk airline))
      (route-risk (get-route-risk origin destination))
      (flight-perf (get-flight-history airline flight-number))
      (base-premium (/ (* coverage-amount (var-get base-rate)) PRECISION))
      (risk-adjustment (calculate-risk-adjustment airline-risk route-risk flight-perf))
      (duration-adjustment (calculate-duration-adjustment duration-days))
      (seasonal-adj (var-get seasonal-multiplier))
      (adjusted-premium (calculate-final-premium base-premium risk-adjustment duration-adjustment seasonal-adj))
      (final-premium (bound-premium adjusted-premium))
      (risk-score (calculate-composite-risk airline-risk route-risk flight-perf))
    )
    
    ;; Cache the result
    (map-set premium-cache
      { airline: airline, flight-number: flight-number, coverage: coverage-amount, duration: duration-days, risk-hash: risk-hash }
      {
        premium: final-premium,
        calculated-at: stacks-block-height,
        risk-score: risk-score,
        base-rate-used: (var-get base-rate)
      }
    )
    
    ;; Record quote request
    (record-quote-request quote-id tx-sender airline flight-number coverage-amount duration-days final-premium risk-score)
    
    (ok final-premium)
  )
)

;; Calculate airline risk multiplier
(define-private (calculate-airline-multiplier (delay-rate uint) (cancellation-rate uint) (reliability-score uint))
  (let
    (
      (combined-risk (+ delay-rate cancellation-rate))
      (reliability-adj (- u10000 (* (- u100 reliability-score) u100)))
      (base-multiplier (+ u10000 (/ combined-risk u2)))
    )
    (/ (* base-multiplier reliability-adj) PRECISION)
  )
)

;; Calculate route risk multiplier
(define-private (calculate-route-multiplier (weather-risk uint) (congestion-risk uint) (distance-factor uint))
  (let
    (
      (environmental-risk (+ weather-risk congestion-risk))
      (distance-adj (if (> distance-factor u1000) (+ u10000 (/ distance-factor u10)) u10000))
    )
    (+ u10000 (+ environmental-risk distance-adj))
  )
)

;; Calculate performance score from historical data
(define-private (calculate-performance-score (on-time-rate uint) (avg-delay-minutes uint))
  (let
    (
      (timeliness-score (/ on-time-rate u100)) ;; Convert basis points to percentage
      (delay-penalty (if (> avg-delay-minutes u30) (- u100 (/ avg-delay-minutes u10)) u100))
    )
    (if (< (+ (/ timeliness-score u2) (/ delay-penalty u2)) u1) u1 (if (> (+ (/ timeliness-score u2) (/ delay-penalty u2)) u100) u100 (+ (/ timeliness-score u2) (/ delay-penalty u2))))
  )
)

;; Calculate composite risk score
(define-private (calculate-composite-risk (airline-risk (optional { delay-rate: uint, cancellation-rate: uint, reliability-score: uint, total-flights: uint, risk-multiplier: uint })) 
                                         (route-risk (optional { weather-risk: uint, congestion-risk: uint, distance-factor: uint, seasonal-variance: uint, route-multiplier: uint })) 
                                         (flight-perf (optional { on-time-rate: uint, avg-delay-minutes: uint, sample-size: uint, last-updated: uint, performance-score: uint })))
  (let
    (
      (airline-score (match airline-risk ar (get reliability-score ar) u50))
      (route-score (match route-risk rr (- u100 (+ (get weather-risk rr) (get congestion-risk rr))) u50))
      (flight-score (match flight-perf fp (get performance-score fp) u50))
    )
    (/ (+ (+ (* airline-score u40) (* route-score u35)) (* flight-score u25)) u100) ;; Weighted average
  )
)

;; Calculate risk adjustment multiplier
(define-private (calculate-risk-adjustment (airline-risk (optional { delay-rate: uint, cancellation-rate: uint, reliability-score: uint, total-flights: uint, risk-multiplier: uint })) 
                                         (route-risk (optional { weather-risk: uint, congestion-risk: uint, distance-factor: uint, seasonal-variance: uint, route-multiplier: uint })) 
                                         (flight-perf (optional { on-time-rate: uint, avg-delay-minutes: uint, sample-size: uint, last-updated: uint, performance-score: uint })))
  (let
    (
      (airline-mult (match airline-risk ar (get risk-multiplier ar) u10000))
      (route-mult (match route-risk rr (get route-multiplier rr) u10000))
      (flight-mult (calculate-flight-multiplier flight-perf))
    )
    (/ (* (* airline-mult route-mult) flight-mult) (* PRECISION PRECISION))
  )
)

;; Calculate flight-specific multiplier
(define-private (calculate-flight-multiplier (flight-perf (optional { on-time-rate: uint, avg-delay-minutes: uint, sample-size: uint, last-updated: uint, performance-score: uint })))
  (match flight-perf
    fp (let
         (
           (perf-score (get performance-score fp))
           (sample-reliability (if (< (/ (get sample-size fp) u10) u100) (/ (get sample-size fp) u10) u100)) ;; More samples = more reliable
         )
         ;; Better performance = lower multiplier
         (+ u8000 (- u4000 (/ (* perf-score sample-reliability) u100)))
       )
    u10000 ;; Default if no flight history
  )
)

;; Calculate duration adjustment
(define-private (calculate-duration-adjustment (duration-days uint))
  (if (<= duration-days u7)
    u10000 ;; No adjustment for short durations
    (+ u10000 (* (- duration-days u7) u100)) ;; Increase premium by 1% per day over 7
  )
)

;; Calculate final premium with all adjustments
(define-private (calculate-final-premium (base-premium uint) (risk-adj uint) (duration-adj uint) (seasonal-adj uint))
  (/ (* (* (* base-premium risk-adj) duration-adj) seasonal-adj) (* (* PRECISION PRECISION) PRECISION))
)

;; Bound premium to min/max limits
(define-private (bound-premium (premium uint))
  (if (< premium MIN-PREMIUM) MIN-PREMIUM (if (> premium MAX-PREMIUM) MAX-PREMIUM premium))
)

;; Calculate risk hash for caching
(define-private (calculate-risk-hash (airline (buff 8)) (flight-number uint) (origin (buff 8)) (destination (buff 8)))
  ;; Simple hash combining inputs (simplified for example)
  (+ (+ flight-number (len airline)) (+ (len origin) (len destination)))
)

;; Record quote request for analytics
(define-private (record-quote-request (quote-id uint) (requester principal) (airline (buff 8)) (flight-number uint) 
                                    (coverage-amount uint) (duration-days uint) (premium uint) (risk-score uint))
  (begin
    (map-set quote-requests
      { quote-id: quote-id }
      {
        requester: requester,
        airline: airline,
        flight-number: flight-number,
        coverage-amount: coverage-amount,
        duration-days: duration-days,
        calculated-premium: premium,
        risk-assessment: risk-score,
        timestamp: stacks-block-height
      }
    )
    (var-set total-quotes (+ quote-id u1))
  )
)

;; Assess airline risk level category
(define-private (assess-airline-risk-level (airline-data { delay-rate: uint, cancellation-rate: uint, reliability-score: uint, total-flights: uint, risk-multiplier: uint }))
  (let
    (
      (combined-issues (+ (get delay-rate airline-data) (get cancellation-rate airline-data)))
    )
    (if (<= combined-issues u1000) RISK-VERY-LOW
      (if (<= combined-issues u2500) RISK-LOW
        (if (<= combined-issues u5000) RISK-MEDIUM
          (if (<= combined-issues u7500) RISK-HIGH
            RISK-VERY-HIGH))))
  )
)

;; Assess route risk level category
(define-private (assess-route-risk-level (route-data { weather-risk: uint, congestion-risk: uint, distance-factor: uint, seasonal-variance: uint, route-multiplier: uint }))
  (let
    (
      (environmental-risk (+ (get weather-risk route-data) (get congestion-risk route-data)))
    )
    (if (<= environmental-risk u25) RISK-VERY-LOW
      (if (<= environmental-risk u50) RISK-LOW
        (if (<= environmental-risk u75) RISK-MEDIUM
          (if (<= environmental-risk u90) RISK-HIGH
            RISK-VERY-HIGH))))
  )
)


