/// Schema version 4: the user's own contact phone, edited in Settings →
/// «اطلاعات صرافی» together with the user's display name.
library;

const List<String> schemaV4 = [
  'ALTER TABLE users ADD COLUMN phone TEXT',
];
