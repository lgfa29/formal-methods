test tcDatabase [main=TestDatabase]:
  assert GuaranteedTransactionProgress in
  (union Database, {TestDatabase});

machine TestDatabase {
  start state Init {
    entry {
      SetupTestCase(2, 3);
    }
  }
}

fun SetupTestCase(numKeys: int, numTxs: int) {
  var i: int;
  var db: Database;
  var initialState: map[string, int];

  i = 1;
  while(i <= numKeys) {
    initialState[format("k{0}", i)] = -1;
    i = i + 1;
  }

  db = new Database(initialState);

  i = 0;
  while(i < numTxs) {
    send db, eTxBegin;
    i = i + 1;
  }
}
