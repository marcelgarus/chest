# Chest

A database that values developer experience.

## In memory or not?

In-memory databases are great for storing small amounts of data.
They're amazingly fast and allows synchronous access (see Hive or Sembast).

Only loading records on an as-needed basis is better suited for large volumes of data though – it improves startup time and makes it possible to store huge amounts of data.

Chest aims to use a hybrid approach – it prefetches and caches a certain amount of records in memory and loads new ones as needed.
You're also able to preload some records so they will always be kept in memory.

TODO: Think about how a synchronous API could work.

## Dart or not?

A low-level language like Rust would be the obvious contender.

Obviously, Rust itself is much more performant than Dart. Also, its advanced memory management features make it safe to quickly spawn lightweight threads operating on the same data structure instead of falling back on Dart's monolithic Isolate model and having to deal with message passing.
For example, that would make it possible to execute a query by spawning numerous threads that search the database in parallel.

Using a low-level wrapper also means we could use established database solutions like SQLite or indexdb. These provide amazing performance for queries as well as advanced indexing capabilities.

That being said, database performance is usually I/O-bound and Dart's `RandomAccessFile` would allow us to implement some indexing and query capabilities in Dart as well.
Together with spawning a separate isolate for each database instance, this would probably also result in reasonable performance, although probably a magnitude slower than a battle-tested native solution.

A great advantage of pure Dart, on the other hand, is that it doesn't require any native configuration or dealing with native build systems – the code automatically runs (almost) everywhere where Dart runs, be that Windows, Linux, MacOS, Android, iOS, or Fuchsia. Only web would need to be handled differently.

Writing everything in Dart does come at the cost of having to implement basic database functionalities, like indizes, but it also mean less overhead dealing with the boundary between native code and Dart and being able to debug across those boundaries.

There are already several native wrapper libraries like <kbd>sqflite</kbd> out there.
So, I believe that using pure Dart puts Chest in a very unique position in that allows for deep integration with the Dart ecosystem and language.

## API

### Collections

You should be able to open a collection inside a database/box and get and set records easily:

```dart
final box = Chest.box('sample');
final users = box.collection<String, String>('users');
users['foo'] = 'bar';
users['foo'] = 'baz';
final baz = await users['foo'];
await users.remove('foo');
```

### Queries

Queries are like `.where` but more limited.
Why's that? Because they're really efficient (they tend to scale with the size of the result set).

```dart
final someUsers = users.query((user) {
  return user.firstName.equals('Marcel')
    & user.lastName.startsWith('G')
    | user.age.isBetween(12, 25)
    | user.age > 20;
}).sortedBy((user) => user.age).limitTo(10);
```

## Debugging

This section only applies to debug mode builds.

For debugging, similar to Dart DevTools, Chest should have a web interface.
It should have some tabs, which contain useful functionality:

- Performance
  - Which chunks are loaded?
  - How long does loading chunks take?
  - Response time and latency of queries?
  - Scheduling information: How many queries are active at a time?
  - Cache hit rates
  - Insert events into the Dart Debugging Timeline and link to it
- Storage
  - Number of chunks
  - File layout
  - Trigger manual compaction?
- Data
  - Collections and their content
  - View and update live data
  - Indexes
  - Watched queries and boxes

## General architecture

Each `Chest.open` call creates a new `Isolate` that handles all interactions with the file.
This means that we can use the faster, synchronous I/O operations.
Also, CPU-heavy tasks like compression don't cause jank in the rest of the app.
And the debugging tooling can inspect which isolates are opened and communicate with all of them separately, making it easy to debug them.
Only the necessary data is transferred to the main isolate.

Objects stored in Chest are called *documents*, or just *docs* for short.

While users access documents using a key, Chest actually has a hidden layer of indirection: The key is first mapped to a document id, which is simply an 64-bit integer.
Using the id, the actual document can be looked up.
The reason for this is that keys can get pretty long, so it's impractical to use it to reference the document in indizes.
Ids are short and have a constant size, which saves lots of memory in those places.
In fact, ids are unique in the whole `Chest` and all documents are internally stored in a single tree structure, which makes cross-collection queries possible.

TODO: Think about id re-use after removing documents.

With this in mind, collections merely become a mapping between keys and (a subset of all) document ids.
To do that efficiently, they maintain a B-tree structure.

TODO: Or do they contain a radix tree?

## Data layout

Most operating systems load files in chunks of around 4 KiB. Most databases use a chunk size of 4 KiB or a multiple of that.  
Chest also organizes its data in those chunks, which allows for updating the data structure and inserting data in the middle (well, actually at the end but the extra indirection abstracts from the actual layout).

These are some chunk types:

- The `MainChunk` is the first chunk and *the* entry point for all actions. It points to several important locations:
  - The first `FreeChunk`.
  - The doc tree, which is an int-to-payload-tree that maps document IDs to the `BucketChunk`s that contain the actual document data.
  - The root box tree, which is a payload-to-int-tree that maps root box names to `BoxChunk`s.
- `FreeChunk`s are empty and free to re-use. They are created when some data gets removed, causing chunks to be freed.
  `FreeChunk`s form a linked list: The first `FreeChunk` is pointed to by the `MainChunk` and each `FreeChunk` points to another one – except the last one, which points to 0, the `MainChunk`.
  The order in which the `FreeChunk`s point to one another doesn't need to correlate with the actual location of the chunks in the file. Rather, the linked list resembles the order in which they were freed.
  Chunks that become free are added at the front of the list and newly reserved chunks are taken from the front. That means if a chunk gets freed and re-used in the same transaction, no data actually needs to be written to disk (because the data is diffed before writing).
- Chunks for int-to-payload-trees (these are implemented as B-plus-trees)
  - `IntToPayloadTreeInnerChunk`
  - `IntToPayloadTreeLeafChunk`
- Chunks for payload-to-int-trees (these are implemented as normal B-trees)
  - `PayloadToIntTreeInnerChunk`
  - `PayloadToIntTreeLeafChunk`
- `BucketChunk`s contain multiple payloads. Payloads that are larger than a threshold get broken up into pieces; only the start will be saved in the `BucketChunk` itself, the rest gets written into `OverflowChunk`s.
- `OverflowChunk`s hold payloads that are too big to efficiently store in a single chunk.
- `BoxChunk`s each contain information about a single box (the box name, stats, payload-to-int-tree from keys to doc-ids, indizes).

## Chest layout

Two users with two posts each, each with two comments.

1x MainChunk: stats
doc tree
  1x IntToPayloadTreeLeafChunk
doc data
  4x BucketChunk
box tree
  1x PayloadToIntTreeLeafChunk
'users' box
  1x BoxChunk
  1x PayloadToIntTreeLeafChunk
2x 'posts', each:
  1x BoxChunk
  1x PayloadToIntTreeLeafChunk
4x 'comments', each:
  1x BoxChunk
  1x PayloadToIntTreeLeafChunk

21 chunks

## Queries

Queries could work by making certain types indexable. One could imagine writing `IndexForType` similar to the existing `AdapterForType`s.
Then, class fields could get annotated with `@Index` to indicate that an index should be generated for them.

```dart
@t(#ab) @taped
class Fruit {
  @TapeField(#a8204)
  @Indexed(#a9mpq)
  final String name;

  @Indexed(#p1029)
  String get lowercaseName => name.toLowercase();
}
```

```
@freezed
abstract class Fruit with _$Fruit {
  @id(#a0pWm)
  const factory Fruit(
    @id(#m8wWx) String name, {
    @required int age,
    Gender gender,
  }) = _Fruit;
}
```

Then, `chestgen` generates:

```dart
@TapeExtension("indexed", Fruit)
class IndexedFruit {
  ...
}
```

Then, `tapegen` generates:

```dart
class FruitAdapter {
  ...

  final indexed = IndexedFruit();
}
```

`Fruit` -> `IndexedFruit` -> `IndexedField`s
`SomeFruit` -> ``



Consider this `User` class:

```dart
// Data class. User-written.
@TapeClass(nextFieldId: 3)
class User {
  User({this.firstname, this.lastName, this.age});

  @TapeField(fieldId: 0)
  final String firstName;

  @TapeField(fieldId: 1)
  final String lastName;

  @Index
  String get name => '$firstName $lastName';

  @Index
  @TapeField(fieldId: 2)
  final int age;
}

// or

@freezed
abstract class User with _$User {
  @TapeClass(nextFieldId: 2)
  factory User(
    @TapeField(0) String firstName,
    @TapeField(fieldId: 0) String firstName,
    @TapeField(fieldId: 1) String lastName,
    @TapeField(fieldId: 2) @Index int age,
  ) = _User;

  @Index
  String get name => '$firstName $lastName';
}
```

Note that the `@Index` annotations can only be used on types that are registered as keys.
Some primitive types like `String` and `int` could already implement them:

```dart
// Keys. Contained in Chest.
extension StringKey on String {
  Bytes toKeyBytes() => utf8.encode(this);
}
extension IntKey on int {
  Bytes toKeyBytes() => ...;
}

Chest
  ..registerKeyType<String>((string) => string.toKey())
  ..registerKeyType<int>((value) => value.toKey());

extension FancyStringIndex on IndexedProperty<String> {
  Query startsWith(String string) {
    final lower = string.toKey();
    final upper = lower + 1;
    return rawIsBetweenInclusive(lower, upper);
  }
}
```

Chest could declare that it runs after <kbd>tapegen</kbd> and handle fields annotated with `@Index`.
Based on the `User` above, this class could get generated:

```dart
// IndexedUser. Generated.
class _IndexedUser extends Indexed<User> {
  final name = IndexedProperty<User, String>((user) => user.name);
  final age = IndexedProperty<User, int>((user) => user.age);
  
  final indexes = <IndexedProperty<User, dynamic>>[name, age];
}

extension QueryableIndexedUser<T> on Box<T, User> {
  QueryResult query(Query Function(_IndexedUser user) queryBuilder) =>
      runQuery(queryBuilder(IndexedUser()));
}
```

This `_IndexedUser` could then get passed into the lambda passed to `query`:

```dart
final someUsers = users.query((user) {
  return user.name.startsWith('Marcel G') | user.age.isBetween(12, 25);
}).sortedBy((user) => user.age).limitTo(10);
```

### Chunky

The lowest layer, chunky, works in a cool way.

Transactions should contain few changes (fit in memory).

```dart
final chunky = Chunky('🌮');

// Transactions are great because of two reasons:
// - They guarantee consistency between all operations.
// - They allow the reuse of in-memory buffers, which are quite expensive to
//   create in Dart.

// You can only access chunks inside transactions. Here's a transaction that
// increases a counter atomically.
chunky.transaction((chunky) {
  // The `chunky` object passed to this lambda is more powerful than the one on
  // the outside – you can access chunks.

  final chunk = chunky[0];
  final counter = chunk.getUint8(0);
  chunk.setUint8(0, counter + 1);
});

// Here's a transaction that calculates something based on data from chunks.
// Note that the in-memory buffer representing the chunk will be re-used in
// later transactions.
var sum = chunky.transaction((chunky) {
  return chunky[0].getUint8(0) + chunky[1].getUint8(0);
});

// This means that you can't re-use chunks outside of transactions lifespans:
Chunk fromTransaction;
chunky.transaction((chunky) {
  fromTransaction = chunky[0];
});
final firstByte = fromTransaction.getUint8(0); // Throws an error.

// If you really need the whole data of the chunk outside of the transaction,
// you need to copy it (save a snapshot of the live chunk):
var snapshot = chunky.read((chunky) => chunky[0].snapshot());

// The exception is for debug use cases.
final snapshot = chunky.debugRead(0);
chunky.debugReadInto(1, snapshot); // More efficient (no hidden allocation).
```
