export const idlFactory = ({ IDL }) => {
  const Subaccount = IDL.Vec(IDL.Nat8);
  const Account = IDL.Record({
    'owner' : IDL.Principal,
    'subaccount' : IDL.Opt(Subaccount),
  });
  const Tokens = IDL.Nat;
  const Value = IDL.Variant({
    'Int' : IDL.Int,
    'Nat' : IDL.Nat,
    'Blob' : IDL.Vec(IDL.Nat8),
    'Text' : IDL.Text,
  });
  const Memo = IDL.Vec(IDL.Nat8);
  const Timestamp = IDL.Nat64;
  const TxIndex = IDL.Nat;
  const TABBToken = IDL.Service({
    'add_to_whitelist' : IDL.Func(
        [IDL.Principal],
        [IDL.Variant({ 'Ok' : IDL.Text, 'Err' : IDL.Text })],
        [],
      ),
    'icrc1_balance_of' : IDL.Func([Account], [Tokens], ['query']),
    'icrc1_decimals' : IDL.Func([], [IDL.Nat8], []),
    'icrc1_fee' : IDL.Func([], [IDL.Nat], []),
    'icrc1_metadata' : IDL.Func(
        [],
        [IDL.Vec(IDL.Tuple(IDL.Text, Value))],
        ['query'],
      ),
    'icrc1_name' : IDL.Func([], [IDL.Text], []),
    'icrc1_symbol' : IDL.Func([], [IDL.Text], []),
    'icrc1_total_supply' : IDL.Func([], [Tokens], []),
    'icrc1_transfer' : IDL.Func(
        [
          IDL.Record({
            'to' : Account,
            'fee' : IDL.Opt(Tokens),
            'memo' : IDL.Opt(Memo),
            'from_subaccount' : IDL.Opt(Subaccount),
            'created_at_time' : IDL.Opt(Timestamp),
            'amount' : Tokens,
          }),
        ],
        [IDL.Variant({ 'Ok' : TxIndex, 'Err' : IDL.Text })],
        [],
      ),
    'mint' : IDL.Func(
        [Account, Tokens],
        [IDL.Variant({ 'Ok' : TxIndex, 'Err' : IDL.Text })],
        [],
      ),
  });
  return TABBToken;
};
export const init = ({ IDL }) => { return []; };
