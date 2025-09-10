;; mineral-token
;; Fungible token representing tokenized shares of rare earth mineral batches.
;; Features: mint/burn by admin, KYC whitelist, allowances, pausable transfers,
;; and supply/metadata management. No cross-contract calls or traits used.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1001))
(define-constant ERR-PAUSED (err u1002))
(define-constant ERR-INSUFFICIENT-BAL (err u1003))
(define-constant ERR-INSUFFICIENT-ALLOW (err u1004))
(define-constant ERR-INVALID-AMOUNT (err u1005))
(define-constant ERR-NOT-WHITELISTED (err u1006))
(define-constant ERR-ALREADY-WHITELISTED (err u1007))
(define-constant ERR-NOT-WHITELIST-MGR (err u1008))
(define-constant ERR-ZERO-ADDRESS (err u1009))

;; Token metadata constants
(define-constant TOKEN-NAME "Mineral Token")
(define-constant TOKEN-SYMBOL "MIN")
(define-constant TOKEN-DECIMALS u6)

;; Data variables
(define-data-var owner principal tx-sender)
(define-data-var paused bool false)
(define-data-var total-supply uint u0)
(define-data-var whitelist-manager principal tx-sender)

;; Balances and allowances
(define-map balances principal uint)
(define-map allowances { owner: principal, spender: principal } uint)

;; Whitelist map for compliant addresses
(define-map whitelist principal bool)

;; Supply cap per project (optional; u0 means uncapped)
(define-data-var supply-cap uint u0)

;; Events (append-only counters)
(define-data-var transfer-counter uint u0)
(define-data-var approval-counter uint u0)

(define-map transfer-events
  uint
  {
    from: (optional principal),
    to: (optional principal),
    amount: uint,
    memo: (string-ascii 50),
    block: uint
  }
)

(define-map approval-events
  uint
  {
    owner: principal,
    spender: principal,
    amount: uint,
    block: uint
  }
)

;; Helpers
(define-private (is-zero-addr (who (optional principal)))
  (is-none who)
)

(define-private (only-owner)
  (begin
    (asserts! (is-eq tx-sender (var-get owner)) ERR-NOT-AUTHORIZED)
    (ok true)
  )
)

(define-private (only-whitelist-manager)
  (begin
    (asserts! (is-eq tx-sender (var-get whitelist-manager)) ERR-NOT-WHITELIST-MGR)
    (ok true)
  )
)

(define-private (require-not-paused)
  (begin
    (asserts! (not (var-get paused)) ERR-PAUSED)
    (ok true)
  )
)

(define-private (require-positive (amount uint))
  (begin
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (ok true)
  )
)

(define-private (is-whitelisted (who principal))
  (default-to false (map-get? whitelist who))
)

(define-private (require-whitelisted (who principal))
  (begin
    (asserts! (is-whitelisted who) ERR-NOT-WHITELISTED)
    (ok true)
  )
)

;; Internal state mutations
(define-private (inc-balance (who principal) (amount uint))
  (let ((cur (default-to u0 (map-get? balances who))))
    (map-set balances who (+ cur amount))
  )
)

(define-private (dec-balance (who principal) (amount uint))
  (let ((cur (default-to u0 (map-get? balances who))))
    (if (>= cur amount)
      (map-set balances who (- cur amount))
      false
    )
  )
)

(define-private (set-allowance (owner-p principal) (spender principal) (amount uint))
  (map-set allowances { owner: owner-p, spender: spender } amount)
)

(define-private (get-allowance (owner-p principal) (spender principal))
  (default-to u0 (map-get? allowances { owner: owner-p, spender: spender }))
)

(define-private (emit-transfer (from (optional principal)) (to (optional principal)) (amount uint) (memo (string-ascii 50)))
  (let ((n (+ (var-get transfer-counter) u1)))
    (var-set transfer-counter n)
    (map-set transfer-events n { from: from, to: to, amount: amount, memo: memo, block: block-height })
  )
)

(define-private (emit-approval (owner-p principal) (spender principal) (amount uint))
  (let ((n (+ (var-get approval-counter) u1)))
    (var-set approval-counter n)
    (map-set approval-events n { owner: owner-p, spender: spender, amount: amount, block: block-height })
  )
)

;; Admin functions
(define-public (set-paused (flag bool))
  (begin
    (try! (only-owner))
    (var-set paused flag)
    (ok flag)
  )
)

(define-public (set-supply-cap (cap uint))
  (begin
    (try! (only-owner))
    (var-set supply-cap cap)
    (ok cap)
  )
)

(define-public (transfer-ownership (new-owner principal))
  (begin
    (try! (only-owner))
    (asserts! (not (is-eq new-owner (var-get owner))) ERR-ZERO-ADDRESS)
    (var-set owner new-owner)
    (ok new-owner)
  )
)

(define-public (set-whitelist-manager (mgr principal))
  (begin
    (try! (only-owner))
    (var-set whitelist-manager mgr)
    (ok mgr)
  )
)

(define-public (whitelist-add (who principal))
  (begin
    (try! (only-whitelist-manager))
    (asserts! (not (is-whitelisted who)) ERR-ALREADY-WHITELISTED)
    (map-set whitelist who true)
    (ok true)
  )
)

(define-public (whitelist-remove (who principal))
  (begin
    (try! (only-whitelist-manager))
    (map-set whitelist who false)
    (ok true)
  )
)

;; Minting and burning
(define-public (mint (to principal) (amount uint) (memo (string-ascii 50)))
  (begin
    (try! (only-owner))
    (try! (require-positive amount))
    (try! (require-whitelisted to))
    (let ((cap (var-get supply-cap))
          (new-supply (+ (var-get total-supply) amount)))
      (asserts! (or (is-eq cap u0) (<= new-supply cap)) ERR-INVALID-AMOUNT)
      (inc-balance to amount)
      (var-set total-supply new-supply)
      (emit-transfer none (some to) amount memo)
      (ok amount)
    )
  )
)

(define-public (burn (amount uint) (memo (string-ascii 50)))
  (begin
    (try! (require-positive amount))
    (asserts! (dec-balance tx-sender amount) ERR-INSUFFICIENT-BAL)
    (var-set total-supply (- (var-get total-supply) amount))
    (emit-transfer (some tx-sender) none amount memo)
    (ok amount)
  )
)

;; ERC20-like transfers
(define-public (transfer (to principal) (amount uint) (memo (string-ascii 50)))
  (begin
    (try! (require-not-paused))
    (try! (require-positive amount))
    (try! (require-whitelisted tx-sender))
    (try! (require-whitelisted to))
    (asserts! (dec-balance tx-sender amount) ERR-INSUFFICIENT-BAL)
    (inc-balance to amount)
    (emit-transfer (some tx-sender) (some to) amount memo)
    (ok true)
  )
)

(define-public (approve (spender principal) (amount uint))
  (begin
    (try! (require-whitelisted tx-sender))
    (set-allowance tx-sender spender amount)
    (emit-approval tx-sender spender amount)
    (ok amount)
  )
)

(define-public (transfer-from (from principal) (to principal) (amount uint) (memo (string-ascii 50)))
  (let ((allow (get-allowance from tx-sender)))
    (begin
      (try! (require-not-paused))
      (try! (require-positive amount))
      (try! (require-whitelisted from))
      (try! (require-whitelisted to))
      (asserts! (>= allow amount) ERR-INSUFFICIENT-ALLOW)
      (asserts! (dec-balance from amount) ERR-INSUFFICIENT-BAL)
      (inc-balance to amount)
      (set-allowance from tx-sender (- allow amount))
      (emit-transfer (some from) (some to) amount memo)
      (ok true)
    )
  )
)

;; Read-only views
(define-read-only (get-name) TOKEN-NAME)
(define-read-only (get-symbol) TOKEN-SYMBOL)
(define-read-only (get-decimals) TOKEN-DECIMALS)
(define-read-only (get-owner) (var-get owner))
(define-read-only (get-paused) (var-get paused))
(define-read-only (get-total-supply) (var-get total-supply))
(define-read-only (get-supply-cap) (var-get supply-cap))
(define-read-only (balance-of (who principal)) (default-to u0 (map-get? balances who)))
(define-read-only (allowance (owner-p principal) (spender principal)) (get-allowance owner-p spender))
(define-read-only (is-on-whitelist (who principal)) (is-whitelisted who))
(define-read-only (get-transfer-event (id uint)) (map-get? transfer-events id))
(define-read-only (get-approval-event (id uint)) (map-get? approval-events id))
(define-read-only (get-transfer-count) (var-get transfer-counter))
(define-read-only (get-approval-count) (var-get approval-counter))
