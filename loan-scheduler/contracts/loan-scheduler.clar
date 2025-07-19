;; Loan Scheduler - Structured Loan Payments
;; Time-locked contract for releasing funds after specified delays

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u401))
(define-constant ERR-LOAN-NOT-FOUND (err u404))
(define-constant ERR-INVALID-AMOUNT (err u400))
(define-constant ERR-PAYMENT-NOT-DUE (err u403))
(define-constant ERR-LOAN-ALREADY-EXISTS (err u409))
(define-constant ERR-INSUFFICIENT-BALANCE (err u402))
(define-constant ERR-LOAN-COMPLETED (err u410))

;; Data Variables
(define-data-var loan-counter uint u0)
(define-data-var contract-owner principal tx-sender)

;; Data Maps
(define-map loans
  { loan-id: uint }
  {
    borrower: principal,
    lender: principal,
    total-amount: uint,
    remaining-amount: uint,
    payment-amount: uint,
    payment-interval: uint,
    next-payment-block: uint,
    payments-made: uint,
    total-payments: uint,
    created-at: uint,
    is-active: bool
  }
)

(define-map payment-history
  { loan-id: uint, payment-number: uint }
  {
    amount: uint,
    block-height: uint,
    timestamp: uint
  }
)

;; Private Functions
(define-private (get-next-loan-id)
  (begin
    (var-set loan-counter (+ (var-get loan-counter) u1))
    (var-get loan-counter)
  )
)

;; Read-only Functions
(define-read-only (get-loan (loan-id uint))
  (map-get? loans { loan-id: loan-id })
)

(define-read-only (get-payment-history (loan-id uint) (payment-number uint))
  (map-get? payment-history { loan-id: loan-id, payment-number: payment-number })
)

(define-read-only (is-payment-due (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan-data
    (and 
      (get is-active loan-data)
      (>= block-height (get next-payment-block loan-data))
      (> (get remaining-amount loan-data) u0)
    )
    false
  )
)

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender))
)

(define-read-only (calculate-total-payments (total-amount uint) (payment-amount uint))
  (/ (+ total-amount payment-amount (- u1)) payment-amount)
)

;; Public Functions

;; Create a new loan with structured payments
(define-public (create-loan 
  (borrower principal)
  (total-amount uint)
  (payment-amount uint)
  (payment-interval uint)
)
  (let
    (
      (loan-id (get-next-loan-id))
      (total-payments (calculate-total-payments total-amount payment-amount))
      (first-payment-block (+ block-height payment-interval))
    )
    (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> payment-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (> payment-interval u0) ERR-INVALID-AMOUNT)
    (asserts! (<= payment-amount total-amount) ERR-INVALID-AMOUNT)
    
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    
    (map-set loans
      { loan-id: loan-id }
      {
        borrower: borrower,
        lender: tx-sender,
        total-amount: total-amount,
        remaining-amount: total-amount,
        payment-amount: payment-amount,
        payment-interval: payment-interval,
        next-payment-block: first-payment-block,
        payments-made: u0,
        total-payments: total-payments,
        created-at: block-height,
        is-active: true
      }
    )
    (ok loan-id)
  )
)

;; Release initial loan amount to borrower
(define-public (release-loan-funds (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan-data
    (begin
      (asserts! (is-eq tx-sender (get lender loan-data)) ERR-NOT-AUTHORIZED)
      (asserts! (get is-active loan-data) ERR-LOAN-COMPLETED)
      (asserts! (is-eq (get payments-made loan-data) u0) ERR-NOT-AUTHORIZED)
      
      (try! (as-contract (stx-transfer? (get total-amount loan-data) tx-sender (get borrower loan-data))))
      (ok true)
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Make a scheduled payment
(define-public (make-payment (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan-data
    (begin
      (asserts! (is-eq tx-sender (get borrower loan-data)) ERR-NOT-AUTHORIZED)
      (asserts! (get is-active loan-data) ERR-LOAN-COMPLETED)
      (asserts! (is-payment-due loan-id) ERR-PAYMENT-NOT-DUE)
      
      (let
        (
          (payment-amount (get payment-amount loan-data))
          (remaining-amount (get remaining-amount loan-data))
          (actual-payment (if (<= remaining-amount payment-amount) remaining-amount payment-amount))
          (new-remaining (- remaining-amount actual-payment))
          (new-payments-made (+ (get payments-made loan-data) u1))
          (next-payment-block (+ block-height (get payment-interval loan-data)))
          (is-loan-complete (is-eq new-remaining u0))
        )
        
        ;; Transfer payment to lender
        (try! (stx-transfer? actual-payment tx-sender (get lender loan-data)))
        
        ;; Record payment history
        (map-set payment-history
          { loan-id: loan-id, payment-number: new-payments-made }
          {
            amount: actual-payment,
            block-height: block-height,
            timestamp: block-height
          }
        )
        
        ;; Update loan data
        (map-set loans
          { loan-id: loan-id }
          (merge loan-data
            {
              remaining-amount: new-remaining,
              payments-made: new-payments-made,
              next-payment-block: (if is-loan-complete u0 next-payment-block),
              is-active: (not is-loan-complete)
            }
          )
        )
        
        (ok { payment-made: actual-payment, loan-completed: is-loan-complete })
      )
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Emergency withdrawal for lender (only if borrower defaults significantly)
(define-public (emergency-withdrawal (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan-data
    (begin
      (asserts! (is-eq tx-sender (get lender loan-data)) ERR-NOT-AUTHORIZED)
      (asserts! (get is-active loan-data) ERR-LOAN-COMPLETED)
      ;; Allow emergency withdrawal if payment is overdue by 2 payment intervals
      (asserts! (>= block-height (+ (get next-payment-block loan-data) (* u2 (get payment-interval loan-data)))) ERR-PAYMENT-NOT-DUE)
      
      (let
        (
          (contract-balance (stx-get-balance (as-contract tx-sender)))
          (withdrawal-amount (if (<= contract-balance (get remaining-amount loan-data)) 
                               contract-balance 
                               (get remaining-amount loan-data)))
        )
        (try! (as-contract (stx-transfer? withdrawal-amount tx-sender (get lender loan-data))))
        
        ;; Mark loan as inactive
        (map-set loans
          { loan-id: loan-id }
          (merge loan-data { is-active: false })
        )
        
        (ok withdrawal-amount)
      )
    )
    ERR-LOAN-NOT-FOUND
  )
)

;; Get loan status
(define-read-only (get-loan-status (loan-id uint))
  (match (map-get? loans { loan-id: loan-id })
    loan-data
    (ok {
      loan-id: loan-id,
      borrower: (get borrower loan-data),
      lender: (get lender loan-data),
      total-amount: (get total-amount loan-data),
      remaining-amount: (get remaining-amount loan-data),
      payment-amount: (get payment-amount loan-data),
      payments-made: (get payments-made loan-data),
      total-payments: (get total-payments loan-data),
      next-payment-due: (get next-payment-block loan-data),
      is-active: (get is-active loan-data),
      payment-overdue: (and 
        (get is-active loan-data)
        (> block-height (get next-payment-block loan-data))
        (> (get remaining-amount loan-data) u0)
      )
    })
    ERR-LOAN-NOT-FOUND
  )
)