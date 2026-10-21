/// Schema version 8: account 3100 is the exchange's initial capital only.
///
/// Customer opening balances post against drawer cash and no longer touch
/// 3100, so its old name ("capital and opening balances") would misstate
/// what the account holds. Renaming is cosmetic — no balances change.
library;

const List<String> schemaV8 = [
  '''
  UPDATE accounts SET name_fa = 'سرمایه اولیه صرافی'
  WHERE code = '3100' AND role = 'openingEquity'
  ''',
];
