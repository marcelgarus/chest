import 'dart:convert';

import 'chest.dart';

void main() async {
  tape.register({
    ...tapers.forDartCore(),
    0: taper.forUser(),
    ...tapers.forDartMath(),
    ...tapers.forDartTypedData(),
    1: taper.forPet(),
  });

  /// Chests are a storage for global, persisted variables.
  print('Main: Opening foo chest');
  final foo = await Chest.open<User>(
    '🌮',
    ifNew: () => User('Marcel', Pet('0')),
  );
  foo.pet.watch().forEach((it) => print('Pet is now $it.'));
  for (var i = 0; i < 2; i++) {
    await Future.delayed(Duration(seconds: 2));
    // Increase Pet's name
    final petName = foo.pet.name.value;
    foo.pet.name.value = '${int.parse(petName) + 1}';
  }
  await foo.close();
}

@tape
class User {
  User(this.name, this.pet);

  final String name;
  final Pet pet;

  String toString() => 'User($name, $pet)';
}

@tape
class Pet {
  Pet(this.name);

  final String name;

  String toString() => 'Pet($name)';
}

// ================================= generated =================================

// User

extension TaperForUser on TaperApi {
  Taper<User> forUser() => _TaperForUser();
}

class _TaperForUser extends ClassTaper<User> {
  Map<String, Object> toFields(User value) {
    return {'name': value.name, 'pet': value.pet};
  }

  User fromFields(Map<String, Object?> fields) {
    return User(fields['name'] as String, fields['pet'] as Pet);
  }
}

extension ChildrenOfUser on Ref<User> {
  Ref<String> get name => child('name');
  Ref<int> get age => child('age');
  Ref<Pet> get pet => child('pet');
}

// Pet

extension TaperForPet on TaperApi {
  Taper<Pet> forPet() => _TaperForPet();
}

class _TaperForPet extends ClassTaper<Pet> {
  Map<String, Object> toFields(Pet value) {
    return {'name': value.name};
  }

  Pet fromFields(Map<String, Object?> fields) {
    return Pet(fields['name'] as String);
  }
}

extension ChildrenOfPet on Ref<Pet> {
  Ref<String> get name => child('name');
}
