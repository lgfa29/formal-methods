enum tOpAction { READ, WRITE}
enum tTxResult { SUCCESS, FAIL }

type tOp = (action: tOpAction, key: string, value: int);
type tTxCommitReq = (tx: Transaction, id: int, snapshot: map[string, int], ops: seq[tOp]);
type tTxCommitResp = (id: int, result: tTxResult);

event eTxBegin;
event eTxCommitReq: tTxCommitReq;
event eTxCommitResp: tTxCommitResp;

module Database = { Database, Transaction };

machine Database {
  // store is the key-value data storage for the database.
  var store: map[string, int];

  // activeTxs is the set of transaction IDs that are currently active.
  var activeTxs: set[int];

  // missedWrites maps a transaction ID to a set of keys that were modified
  // by other transactions while the transaction was active.
  var missedWrites: map[int, set[string]];

  // idCounter provides a monotonically increasing unique identifier for each
  // transaction.
  var idCounter: int;

  start state Init{
    entry (initialState: map[string, int]) {
      store = initialState;

      goto Active;
    }
  }

  state Active{
    on eTxBegin do {
      var snapshot: map[string, int];
      var key: string;

      // Snapshot current store for the new transaction.
      foreach(key in keys(store)) {
        snapshot[key] = store[key];
      }

      // Increment transaction ID counter and track new transaction as active.
      idCounter = idCounter + 1;
      activeTxs += (idCounter);
      new Transaction((db = this, id = idCounter, snapshot = snapshot));
    }

    on eTxCommitReq do (req: tTxCommitReq) {
      var txId: int;
      var writes: set[string];
      var key: string;
      var op: tOp;

      // Find transaction writes to check for conflicts.
      foreach(op in req.ops) {
        if(op.action == WRITE) {
          writes += (op.key);
        }
      }

      // Verify if the transaction modify a key that was written to after its
      // snapshot was created.
      if(req.id in missedWrites) {
        foreach(key in writes) {
          if(key in missedWrites[req.id]) {
            print format("Transaction {0} rejected because it missed write to {1}.", req.id, key);
            send req.tx, eTxCommitResp, (id = req.id, result = FAIL);
            return;
          }
        }
      }

      // Stop tracking the transaction as active.
      activeTxs -= (req.id);

      // Update the set of keys that were written to by this transactions into
      // the missed writes set of the other active transactions so they can
      // check for conflicts on commit.
      foreach(txId in activeTxs) {
        if(!(txId in missedWrites)) {
          missedWrites[txId] = default(set[string]);
        }
        foreach(key in writes) {
          missedWrites[txId] += (key);
        }
      }

      // Apply transaction changes.
      foreach(key in writes) {
        store[key] = req.snapshot[key];
      }
      send req.tx, eTxCommitResp, (id = req.id, result = SUCCESS);
    }
  }
}

machine Transaction {
  // db is used to communicate with the Database machine running the
  // transaction.
  var db: Database;

  // id is the unique identifier for the transaction.
  var id: int;

  // snapshot is the state copy provided by the database when the transaction
  // started.
  var snapshot: map[string, int];

  // reads is the set of keys the transaction will read. They do not modify
  // state but are important to check for correctness.
  var reads: set[string];

  // writes is the set of keys the transaction will write to.
  var writes: set[string];

  // ops is the set of operations performd by the transaction. It is important
  // to keep track of them to verify correctness of the transaction isolation.
  var ops: seq[tOp];

  start state Init {
    entry (input: (db: Database, id: int, snapshot: map[string, int])) {
      var i: int;

      db = input.db;
      id = input.id;
      snapshot = input.snapshot;

      // Pick random sets of keys to read and write.
      i = choose(5);
      while(i > 0) {
        reads += (choose(keys(snapshot)));
        i = i - 1;
      }

      i = choose(5);
      while(i > 0) {
        writes += (choose(keys(snapshot)));
        i = i - 1;
      }

      goto Reading;
    }
  }

  state Reading {
    entry {
      var read: string;

      foreach(read in reads) {
	      ops += (sizeof(ops), (action = READ, key = read, value = -1));
      }

      goto Writing;
    }
  }

  state Writing {
    entry {
      var write: string;

      foreach(write in writes) {
        snapshot[write] = id;
        ops += (sizeof(ops), (action = WRITE, key = write, value = id));
      }

      goto Commit;
    }
  }

  state Commit {
    entry {
      send db, eTxCommitReq, (tx = this, id = id, snapshot = snapshot, ops = ops);
    }

    on eTxCommitResp do (resp: tTxCommitResp) {
      if(resp.result == FAIL) {
        print format("Transaction {0} failed.", id);
      } else {
        print format("Transaction {0} succeeded.", id);
      }
    }
  }
}
