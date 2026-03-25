;; contract title
;; AI-Enhanced Multisig Wallet Security

;; <add a description here>
;; This smart contract implements an advanced multisignature wallet with an AI-driven security layer.
;; An authorized AI oracle analyzes proposed transactions and assigns a risk score (0-100).
;; The required number of signatures scales dynamically based on this AI risk score,
;; with higher risk requiring higher consensus. It protects against common vulnerabilities 
;; like replay attacks (using nonces) and unauthorized execution (strict principal checks).
;; 
;; New additions include the ability to remove owners, revoke confirmations,
;; cancel pending transactions, update the oracle, and extensive read-only state queries
;; to provide complete transparency into the contract's operations.

;; ---------------------------------------------------------
;; constants
;; ---------------------------------------------------------

;; The initial contract deployer and administrator for managing owners
(define-constant contract-owner tx-sender)

;; Error codes for consistent failure handling
(define-constant err-owner-only (err u100))
(define-constant err-oracle-only (err u101))
(define-constant err-tx-not-found (err u102))
(define-constant err-already-executed (err u103))
(define-constant err-already-confirmed (err u104))
(define-constant err-insufficient-sigs (err u105))
(define-constant err-ai-blocked (err u106))
(define-constant err-unscored (err u107))
(define-constant err-not-submitter (err u108))
(define-constant err-tx-revoked (err u109))
(define-constant err-not-confirmed (err u110))
(define-constant err-min-owners-reached (err u111))

;; ---------------------------------------------------------
;; data maps and vars
;; ---------------------------------------------------------

;; The designated AI oracle capable of scoring transactions
(define-data-var ai-oracle principal 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)

;; Tracks authorized owners (true = active owner, false/none = inactive/not owner)
(define-map owners principal bool)

;; Tracks the total number of owners to calculate signature thresholds dynamically
;; We require at least 1 owner at all times
(define-data-var total-owners uint u3)

;; Transaction nonce to prevent replay attacks and ensure unique tx IDs
(define-data-var tx-nonce uint u0)

;; Main transaction registry storing all relevant data for a proposal
(define-map transactions
    uint
    {
        submitter: principal,
        recipient: principal,
        amount: uint,
        executed: bool,
        revoked: bool,
        risk-score: (optional uint),
        confirmations: uint
    }
)

;; Tracks individual confirmations to prevent double-voting
;; maps {tx-id, owner} to boolean (true if confirmed)
(define-map tx-confirmations { tx-id: uint, owner: principal } bool)

;; ---------------------------------------------------------
;; private functions
;; ---------------------------------------------------------

;; Helper to check if a principal is an authorized owner
;; @param caller: The principal to check
;; @returns boolean indicating if the principal is an active owner
(define-private (is-owner (caller principal))
    (default-to false (map-get? owners caller))
)

;; ---------------------------------------------------------
;; read-only functions
;; ---------------------------------------------------------

;; Retrieve full details of a transaction by its ID
;; @param tx-id: The transaction nonce
(define-read-only (get-transaction (tx-id uint))
    (map-get? transactions tx-id)
)

;; Check if a specific owner has confirmed a transaction
;; @param tx-id: The transaction nonce
;; @param owner: The principal to check
(define-read-only (has-confirmed (tx-id uint) (owner principal))
    (default-to false (map-get? tx-confirmations { tx-id: tx-id, owner: owner }))
)

;; Get the current total number of owners
(define-read-only (get-total-owners)
    (var-get total-owners)
)

;; Get the current transaction nonce (next ID to be used)
(define-read-only (get-tx-nonce)
    (var-get tx-nonce)
)

;; Check the active status of an owner
;; @param owner: The principal to check
(define-read-only (get-owner-status (owner principal))
    (is-owner owner)
)

;; Get the currently active AI oracle principal
(define-read-only (get-ai-oracle)
    (var-get ai-oracle)
)

;; ---------------------------------------------------------
;; public functions - Administrative
;; ---------------------------------------------------------

;; Initialize the contract with a new owner
;; @param new-owner: The principal to add as an owner
(define-public (add-owner (new-owner principal))
    (begin
        ;; Only the contract deployer can manage owners
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        ;; Update state
        (map-set owners new-owner true)
        (var-set total-owners (+ (var-get total-owners) u1))
        (ok true)
    )
)

;; Remove an existing owner
;; @param old-owner: The principal to remove from the owners list
(define-public (remove-owner (old-owner principal))
    (begin
        ;; Only the contract deployer can manage owners
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        ;; Ensure we don't drop below 1 owner
        (asserts! (> (var-get total-owners) u1) err-min-owners-reached)
        ;; Ensure the target is actually an owner
        (asserts! (is-owner old-owner) err-owner-only)
        
        ;; Update state
        (map-set owners old-owner false)
        (var-set total-owners (- (var-get total-owners) u1))
        (ok true)
    )
)

;; Update the AI Oracle address
;; @param new-oracle: The principal to set as the new AI Oracle
(define-public (update-ai-oracle (new-oracle principal))
    (begin
        ;; Only the contract deployer can manage the oracle
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set ai-oracle new-oracle)
        (ok true)
    )
)

;; ---------------------------------------------------------
;; public functions - Transaction Lifecycle
;; ---------------------------------------------------------

;; Propose a new transaction to be evaluated and signed
;; @param recipient: The principal receiving the funds
;; @param amount: The amount of STX to transfer
(define-public (submit-tx (recipient principal) (amount uint))
    (let
        ((tx-id (var-get tx-nonce)))
        
        ;; Ensure caller is an active owner
        (asserts! (is-owner tx-sender) err-owner-only)
        
        ;; Register the transaction proposal
        (map-set transactions tx-id {
            submitter: tx-sender,
            recipient: recipient,
            amount: amount,
            executed: false,
            revoked: false,
            risk-score: none,
            confirmations: u0
        })
        
        ;; Increment nonce to prevent replay attacks
        (var-set tx-nonce (+ tx-id u1))
        (ok tx-id)
    )
)

;; Cancel a transaction before it is executed
;; @param tx-id: The transaction ID to revoke
(define-public (revoke-tx (tx-id uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) err-tx-not-found)))
        
        ;; Only the original submitter can revoke the transaction
        (asserts! (is-eq tx-sender (get submitter tx)) err-not-submitter)
        ;; Cannot revoke an already executed transaction
        (asserts! (not (get executed tx)) err-already-executed)
        ;; Cannot revoke an already revoked transaction
        (asserts! (not (get revoked tx)) err-tx-revoked)
        
        ;; Mark as revoked
        (map-set transactions tx-id (merge tx { revoked: true }))
        (ok true)
    )
)

;; AI Oracle assigns a risk score (0-100) to a transaction
;; @param tx-id: The transaction to score
;; @param score: The assigned risk score (0 = lowest risk, 100 = highest risk)
(define-public (assign-ai-risk-score (tx-id uint) (score uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) err-tx-not-found)))
        
        ;; Ensure only the active AI oracle can call this
        (asserts! (is-eq tx-sender (var-get ai-oracle)) err-oracle-only)
        ;; Cannot score executed or revoked transactions
        (asserts! (not (get executed tx)) err-already-executed)
        (asserts! (not (get revoked tx)) err-tx-revoked)
        
        ;; Update the transaction with the new score
        (map-set transactions tx-id (merge tx { risk-score: (some score) }))
        (ok true)
    )
)

;; Owners confirm the transaction
;; @param tx-id: The transaction ID to confirm
(define-public (confirm-tx (tx-id uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) err-tx-not-found)))
        
        ;; Caller must be an active owner
        (asserts! (is-owner tx-sender) err-owner-only)
        ;; Cannot confirm executed or revoked transactions
        (asserts! (not (get executed tx)) err-already-executed)
        (asserts! (not (get revoked tx)) err-tx-revoked)
        ;; Prevent double voting
        (asserts! (is-none (map-get? tx-confirmations { tx-id: tx-id, owner: tx-sender })) err-already-confirmed)
        
        ;; Record the confirmation
        (map-set tx-confirmations { tx-id: tx-id, owner: tx-sender } true)
        ;; Increment the confirmation count
        (map-set transactions tx-id (merge tx { confirmations: (+ (get confirmations tx) u1) }))
        (ok true)
    )
)

;; Owners can revoke their previous confirmation
;; @param tx-id: The transaction ID to un-confirm
(define-public (revoke-confirmation (tx-id uint))
    (let
        ((tx (unwrap! (map-get? transactions tx-id) err-tx-not-found)))
        
        ;; Caller must be an active owner
        (asserts! (is-owner tx-sender) err-owner-only)
        ;; Cannot un-confirm executed or revoked transactions
        (asserts! (not (get executed tx)) err-already-executed)
        (asserts! (not (get revoked tx)) err-tx-revoked)
        ;; Must have confirmed previously
        (asserts! (default-to false (map-get? tx-confirmations { tx-id: tx-id, owner: tx-sender })) err-not-confirmed)
        
        ;; Remove the confirmation
        (map-delete tx-confirmations { tx-id: tx-id, owner: tx-sender })
        ;; Decrement the confirmation count
        (map-set transactions tx-id (merge tx { confirmations: (- (get confirmations tx) u1) }))
        (ok true)
    )
)


