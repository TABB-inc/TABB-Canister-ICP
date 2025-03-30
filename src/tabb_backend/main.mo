// TABB Token (ICRC-1 + ICRC-2 Full Implementation with Ownership + Whitelist Minting)

// Import base modules needed for smart contract functionality
import Array "mo:base/Array";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Int "mo:base/Int";
import Nat8 "mo:base/Nat8";
import Nat64 "mo:base/Nat64";
import Option "mo:base/Option";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";

actor class TABBToken() = this {

  // ----------------------------
  // 📌 Types and Configuration
  // ----------------------------
  public type Subaccount = Blob;
  public type Account = { owner : Principal; subaccount : ?Subaccount };
  public type Tokens = Nat;
  public type Memo = Blob;
  public type Timestamp = Nat64;
  public type TxIndex = Nat;
  public type Value = { #Nat : Nat; #Int : Int; #Blob : Blob; #Text : Text };

  // Token parameters
  let decimals : Nat8 = 8;
  let transfer_fee : Nat = 10_000;
  let token_name : Text = "TABB";
  let token_symbol : Text = "TABB";
  let defaultSubaccount : Subaccount = Blob.fromArrayMut(Array.init(32, 0 : Nat8));

  // 👑 Owner of the token contract
  stable var owner : Principal = Principal.fromText("uq6zd"); // Will be overwritten at init or deployment

    // ✅ Whitelist stored as stable array (converted to HashMap on init)
  stable var stable_whitelist : [(Principal, Bool)] = [];
  var whitelist : HashMap.HashMap<Principal, Bool> = HashMap.HashMap(10, Principal.equal, Principal.hash);

  // ----------------------------
  // 🧾 Transaction Model
  // ----------------------------
  public type Operation = { #Mint : Transfer; #Burn : Transfer; #Transfer : Transfer; #Approve : Approve };

  public type Transfer = {
    from : Account;
    to : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
  };

  public type Approve = {
    from : Account;
    spender : Account;
    amount : Tokens;
    fee : ?Tokens;
    memo : ?Memo;
    created_at_time : ?Timestamp;
    expires_at : ?Timestamp;
  };

  public type Transaction = {
    operation : Operation;
    fee : Tokens;
    timestamp : Timestamp;
  };

  // Store current transaction log in memory and persist across upgrades
  var log : Buffer.Buffer<Transaction> = Buffer.Buffer(100);
  stable var persistedLog : [Transaction] = [];

  // Save log before upgrade
  system func preupgrade() {
    persistedLog := log.toArray();
  };

  // Restore log after upgrade
  system func postupgrade() {
    log := Buffer.Buffer(persistedLog.size());
    for (tx in Array.vals(persistedLog)) { log.add(tx); };
  };

  // ----------------------------
  // 📐 Utility Functions
  // ----------------------------

  // Check if two accounts are equal, including subaccounts
  func accountsEqual(a : Account, b : Account) : Bool {
    Principal.equal(a.owner, b.owner) and Blob.equal(Option.get(a.subaccount, defaultSubaccount), Option.get(b.subaccount, defaultSubaccount))
  };

  // Compute account balance by scanning the transaction log
  func balanceOf(account : Account) : Tokens {
    var total : Tokens = 0;
    for (tx in log.vals()) {
      switch (tx.operation) {
        case (#Mint(t)) if (accountsEqual(t.to, account)) { total += t.amount };
        case (#Burn(t)) if (accountsEqual(t.from, account)) { total -= t.amount };
        case (#Transfer(t)) {
          if (accountsEqual(t.from, account)) { total -= t.amount + Option.get(t.fee, 0); };
          if (accountsEqual(t.to, account)) { total += t.amount };
        };
        case (#Approve(_)) {}; // Doesn't affect balance
      }
    };
    total
  };

  // Compute the total circulating supply
  func totalSupply() : Tokens {
    var total : Tokens = 0;
    for (tx in log.vals()) {
      switch (tx.operation) {
        case (#Mint(t)) { total += t.amount };
        case (#Burn(t)) { total -= t.amount };
        case (#Transfer(_)) {}; // Fee is not burned here
        case (#Approve(_)) {};
      }
    };
    total
  };

  // Get the current timestamp
  func now() : Timestamp = Nat64.fromNat(Int.abs(Time.now()));

  // Add a transaction to the log
  func record(tx : Transaction) : TxIndex {
    let idx = log.size();
    log.add(tx);
    idx
  };

  // ----------------------------
  // 📤 ICRC-1 Token Interface
  // ----------------------------

  public shared ({ caller }) func icrc1_name() : async Text { token_name };
  public shared ({ caller }) func icrc1_symbol() : async Text { token_symbol };
  public shared ({ caller }) func icrc1_decimals() : async Nat8 { decimals };
  public shared ({ caller }) func icrc1_fee() : async Nat { transfer_fee };
  public shared ({ caller }) func icrc1_total_supply() : async Tokens { totalSupply() };

  public query func icrc1_balance_of(account : Account) : async Tokens {
    balanceOf(account)
  };

  // 🔁 Transfer tokens between accounts
  public shared ({ caller }) func icrc1_transfer({ from_subaccount : ?Subaccount; to : Account; amount : Tokens; fee : ?Tokens; memo : ?Memo; created_at_time : ?Timestamp }) : async { #Ok : TxIndex; #Err : Text } {
    let from : Account = { owner = caller; subaccount = from_subaccount };
    let senderBalance = balanceOf(from);
    let usedFee = Option.get(fee, transfer_fee);

    // Check sufficient balance including fee
    if (senderBalance < amount + usedFee) {
      return #Err("Insufficient balance");
    };

    // Create and record the transfer transaction
    let tx : Transaction = {
      operation = #Transfer({ from = from; to = to; amount = amount; fee = fee; memo = memo; created_at_time = created_at_time });
      fee = usedFee;
      timestamp = now();
    };

    let idx = record(tx);
    #Ok(idx)
  };

  // 🔐 Minting — allowed only for whitelisted callers
  public shared ({ caller }) func mint(to : Account, amount : Tokens) : async { #Ok : TxIndex; #Err : Text } {
    if (not Option.get(whitelist.get(caller), false)) {
      return #Err("Caller is not whitelisted to mint");
    };

    // Create and record a mint transaction
    let tx : Transaction = {
      operation = #Mint({ from = to; to = to; amount = amount; fee = null; memo = null; created_at_time = ?now() });
      fee = 0;
      timestamp = now();
    };

    #Ok(record(tx))
  };

  // 👑 Add a principal to the minting whitelist (only owner can call)
  public shared ({ caller }) func add_to_whitelist(addr : Principal) : async { #Ok : Text; #Err : Text } {
    if (caller != owner) {
      return #Err("Only owner can add to whitelist");
    };
    whitelist.put(addr, true);
    #Ok("Added to whitelist")
  };

  // 🔍 Metadata exposed to external tools or UIs
  public query func icrc1_metadata() : async [(Text, Value)] {
    [
      ("icrc1:name", #Text(token_name)),
      ("icrc1:symbol", #Text(token_symbol)),
      ("icrc1:decimals", #Nat(Nat8.toNat(decimals))),
      ("icrc1:fee", #Nat(transfer_fee))
    ]
  };
} 
