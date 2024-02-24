// GuaranteedTransactionProgress is a liveness property that checks that every
// transaction that starts is guaranteed to eventually commit.
spec GuaranteedTransactionProgress observes eTxBegin, eTxCommitResp {
  var pendingTx: int;

  start state NoTx{
    on eTxBegin goto PendingTx with {
      pendingTx = pendingTx + 1;
    }
  }

  // PendingTx is a hot state that the monitor must eventually leave.
  hot state PendingTx {
    on eTxBegin do {
      pendingTx = pendingTx + 1;
    }

    on eTxCommitResp do  {
      pendingTx = pendingTx - 1;
      if(pendingTx == 0 ) {
        goto NoTx;
      }
    }
  }
}

// TODO: add correctness property validation.
// https://muratbuffalo.blogspot.com/2022/07/automated-validation-of-state-based.html
// https://muratbuffalo.blogspot.com/2023/09/a-snapshot-isolated-database-modeling.html
